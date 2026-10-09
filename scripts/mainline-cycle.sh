#!/bin/bash
# mainline-cycle.sh <tag> [extra cmdline]: one bring-up round from the laptop.
#   1. sync port/quigon/mainline (DTS, init) to the build host (DGX Spark), 2. build Image + DTB there,
#   3. fetch, pack and arm the boot-once slot (mainline-pack.sh), 4. reboot the Chromebook, 5. wait for Omarchy
#   to come back (the test kernel reboots itself; panic=5 / watchdog), 6. print the test boot's log (mainline-log).
set -euo pipefail
tag=${1:?tag}; extra=${2:-}
here=$(cd "$(dirname "$0")" && pwd); M=$here/../port/quigon/mainline
BH=${QUIGON_BUILD_HOST:-user@build-host}; CB=${QUIGON_HOST:-root@192.168.0.22}
scp -q "$M/mt8189-quigon.dts" "$M/mt8189-pinfunc.h" "$BH:quigon-kernel/linux-next/arch/arm64/boot/dts/mediatek/"
[[ -n ${RECONFIG:-} ]] && { scp -q "$here/mainline-config.sh" "$BH:quigon-kernel/"; ssh "$BH" 'cd ~/quigon-kernel && ./mainline-config.sh linux-next build-s1 initramfs'; }
scp -q "$M/init-stage1.sh" "$BH:quigon-kernel/initramfs/init"
ssh "$BH" 'chmod 755 ~/quigon-kernel/initramfs/init && cd ~/quigon-kernel && make -s -j20 ARCH=arm64 O=$HOME/quigon-kernel/build-s1 -C linux-next Image mediatek/mt8189-quigon.dtb > build-s1.log 2>&1 || { grep -E "error|Error" build-s1.log | head -20; exit 1; }'
L=$(mktemp -d); trap 'rm -rf "$L"' EXIT
mkdir -p "$L/arch/arm64/boot/dts/mediatek"
scp -q "$BH:quigon-kernel/build-s1/arch/arm64/boot/Image" "$L/arch/arm64/boot/"
scp -q "$BH:quigon-kernel/build-s1/arch/arm64/boot/dts/mediatek/mt8189-quigon.dtb" "$L/arch/arm64/boot/dts/mediatek/"
echo "Image $(stat -c %s "$L/arch/arm64/boot/Image") bytes"
"$here/mainline-pack.sh" "$L" "$tag" "$extra"
ssh "$CB" 'sync; systemctl reboot' || true
sleep 15
for i in $(seq 1 72); do
  timeout 8 ssh -o ConnectTimeout=5 -o BatchMode=yes "$CB" true 2>/dev/null && { echo "Omarchy back after ~$((i*5+15)) s"; break; }
  sleep 5
  (( i == 72 )) && { echo "no SSH after 6 min: the test kernel probably hung (needs a power-button press)"; exit 2; }
done
ssh "$CB" 'grep -o "quigon.test=[^ ]*" /proc/cmdline && echo "WARNING: still in the test kernel?"; mainline-log'
