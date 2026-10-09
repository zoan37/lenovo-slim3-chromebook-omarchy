#!/bin/bash
# mainline-cycle.sh <tag> [extra cmdline]: one bring-up round from the laptop.
#   1. sync port/quigon/mainline (DTS, init) to the build host (DGX Spark), 2. build Image + DTB there,
#   3. fetch, pack and arm the boot-once slot (mainline-pack.sh), 4. reboot the Chromebook, 5. wait for Omarchy
#   to come back (the test kernel reboots itself; panic=5 / watchdog), 6. print the test boot's log (mainline-log).
set -euo pipefail
tag=${1:?tag}; extra=${2:-}
here=$(cd "$(dirname "$0")" && pwd); M=$here/../port/quigon/mainline
BH=${QUIGON_BUILD_HOST:?set QUIGON_BUILD_HOST=user@build-host}; CB=${QUIGON_HOST:-root@192.168.0.22}
scp -q "$M"/mt8189-quigon*.dts "$M/mt8189-pinfunc.h" "$BH:quigon-kernel/linux-next/arch/arm64/boot/dts/mediatek/"
[[ -n ${RECONFIG:-} ]] && { scp -q "$here/mainline-config.sh" "$BH:quigon-kernel/"; ssh "$BH" 'cd ~/quigon-kernel && ./mainline-config.sh linux-next build-s1 initramfs'; }
scp -q "$M/init-stage1.sh" "$BH:quigon-kernel/initramfs/init"
ssh "$BH" 'chmod 755 ~/quigon-kernel/initramfs/init && cd ~/quigon-kernel && make -s -j20 ARCH=arm64 O=$HOME/quigon-kernel/build-s1 -C linux-next Image mediatek/mt8189-quigon.dtb mediatek/mt8189-quigon-nopcie.dtb > build-s1.log 2>&1 || { grep -E "error|Error" build-s1.log | head -20; exit 1; }'
L=$(mktemp -d); trap 'rm -rf "$L"' EXIT
mkdir -p "$L/arch/arm64/boot/dts/mediatek"
scp -q "$BH:quigon-kernel/build-s1/arch/arm64/boot/Image" "$L/arch/arm64/boot/"
scp -q "$BH:quigon-kernel/build-s1/arch/arm64/boot/dts/mediatek/mt8189-quigon*.dtb" "$L/arch/arm64/boot/dts/mediatek/"
echo "Image $(stat -c %s "$L/arch/arm64/boot/Image") bytes"
"$here/mainline-pack.sh" "$L" "$tag" "$extra"
ssh "$CB" 'sync; systemctl reboot' || true
sleep 15
# The test kernel (if it gets Wi-Fi) answers on the same address with its own dropbear host key: don't record keys.
T=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
for i in $(seq 1 72); do
  if cmd=$(timeout 8 ssh "${T[@]}" "$CB" cat /proc/cmdline 2>/dev/null); then
    if [[ $cmd == *quigon.test=* ]]; then
      echo "TEST KERNEL is up on the network after ~$((i*5+15)) s ($(grep -o 'quigon.test=[^ ]*' <<<"$cmd")); its log so far:"
      ssh "${T[@]}" "$CB" 'dmesg | grep "QM:" | sed "s/^.*QM: /QM: /"; echo "== errors:"; dmesg | grep -i -E "error|fail|warn|unable" | grep -v QM: | head -40'
      echo "(it stays up ~20 min; ssh ${T[*]} $CB  to debug, 'touch /tmp/reboot-now' to return to Omarchy)"
      exit 0
    fi
    echo "Omarchy back after ~$((i*5+15)) s"
    ssh "${T[@]}" "$CB" mainline-log
    exit 0
  fi
  # Every minute, also look for the test kernel elsewhere on the /24 (its DHCP client may get another address).
  if (( i % 12 == 0 )); then
    net=${CB#*@}; net=${net%.*}
    for h in $(seq 1 254); do (timeout 1 bash -c "exec 3<>/dev/tcp/$net.$h/22" 2>/dev/null && echo $net.$h) & done | sort > /tmp/.qscan.$$; wait
    for ip in $(cat /tmp/.qscan.$$); do
      c=$(timeout 6 ssh "${T[@]}" root@$ip cat /proc/cmdline 2>/dev/null) || continue
      [[ $c == *quigon.test=* ]] || continue
      echo "TEST KERNEL is up at $ip (not ${CB#*@}) after ~$((i*5+15)) s; its log so far:"
      ssh "${T[@]}" root@$ip 'dmesg | grep "QM:" | sed "s/^.*QM: /QM: /"; echo "== errors:"; dmesg | grep -i -E "error|fail|warn|unable" | grep -v QM: | head -40'
      rm -f /tmp/.qscan.$$; exit 0
    done; rm -f /tmp/.qscan.$$
  fi
  sleep 5
done
echo "no SSH after 6 min: the test kernel probably hung (needs a power-button press)"; exit 2
