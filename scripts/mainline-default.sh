#!/bin/bash
# mainline-default.sh <tag>: make the mainline kernel in the build host's tree the Chromebook's default boot
# (quigon-kernel, KERN-B; Omarchy on the ChromeOS kernel in KERN-C stays the fallback, the old default the rollback).
#   1. build it on QUIGON_BUILD_HOST with LOCALVERSION=-<tag>: a release of its own, so its modules
#      (/usr/lib/modules/<release>) aren't overwritten by the next test build (mainline-full.sh),
#   2. install those modules on the Chromebook, pack Image + DTB as a FIT (mainline-pack.sh NOARM=1),
#   3. quigon-kernel install: KERN-B, 2 tries per boot, handed back by boot-good after every boot that comes up.
# REBOOT=1 reboots into it and waits. EXTRA=<cmdline> replaces the default extra arguments.
# The next plain build in the same build dir (no LOCALVERSION) is the "-quigon+" test release again.
set -euo pipefail
tag=${1:?tag (letters, digits, . _ -)}
[[ $tag =~ ^[A-Za-z0-9._-]+$ ]] || { echo "tag: letters, digits, . _ -"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
BH=${QUIGON_BUILD_HOST:?set QUIGON_BUILD_HOST=user@build-host}; BD=${BUILD_DIR:-build-s1}; DTB=${DTB:-mt8189-quigon-all}
# the watchdog armed at boot catches a hang before userspace (a reset uses up one of the two tries)
extra=${EXTRA-mtk_wdt.start_timeout=31}
addrs=${QUIGON_ADDRS:-192.168.0.22 192.168.0.27}
T=(-o ConnectTimeout=4 -o BatchMode=yes)
cb=""; for ip in $addrs; do timeout 6 ssh "${T[@]}" root@$ip true 2>/dev/null && { cb=root@$ip; break; }; done
[[ -n $cb ]] || { echo "Chromebook not reachable on $addrs"; exit 1; }
M="make -s ARCH=arm64 O=\$HOME/quigon-kernel/$BD -C \$HOME/quigon-kernel/linux-next LOCALVERSION=-$tag"
echo "building $tag on $BH"
ssh "$BH" "$M -j\$(nproc) Image modules mediatek/$DTB.dtb < /dev/null"
V=$(ssh "$BH" "$M kernelrelease")
echo "installing modules for $V on $cb"
ssh "$BH" "set -e; cd ~/quigon-kernel; rm -rf modroot-$BD; $M modules_install INSTALL_MOD_PATH=\$HOME/quigon-kernel/modroot-$BD INSTALL_MOD_STRIP=1 < /dev/null; cd modroot-$BD/lib/modules; rm -f $V/build $V/source; tar czf - $V" |
  ssh "${T[@]}" "$cb" "set -e; rm -rf /usr/lib/modules/.$V.new; mkdir /usr/lib/modules/.$V.new; tar xzf - -C /usr/lib/modules/.$V.new; rm -rf /usr/lib/modules/$V; mv /usr/lib/modules/.$V.new/$V /usr/lib/modules/$V; rmdir /usr/lib/modules/.$V.new; depmod $V"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/arch/arm64/boot/dts/mediatek"
scp -q "$BH:quigon-kernel/$BD/arch/arm64/boot/Image" "$W/arch/arm64/boot/"
scp -q "$BH:quigon-kernel/$BD/arch/arm64/boot/dts/mediatek/$DTB.dtb" "$W/arch/arm64/boot/dts/mediatek/"
QUIGON_HOST=$cb FULL=1 NOARM=1 DTB=$DTB "$here/mainline-pack.sh" "$W" "$tag" "$extra"
ssh "${T[@]}" "$cb" "quigon-kernel install /root/kern-backup/$tag.fit /root/kern-backup/$tag.cmdline $tag $V"
[[ -n ${REBOOT:-} ]] || { echo "default set; it boots at the next reboot"; exit 0; }
ssh "${T[@]}" "$cb" 'sync; systemctl reboot' 2>/dev/null || true
sleep 25
for i in $(seq 1 60); do
  for ip in $addrs; do
    if c=$(timeout 6 ssh "${T[@]}" root@$ip 'uname -r; grep -o "quigon\.default=[^ ]*" /proc/cmdline || echo "on the ChromeOS kernel (fallback)"' 2>/dev/null); then
      echo "up at $ip after ~$((25 + i * 6)) s: $(tr '\n' ' ' <<<"$c")"; exit 0
    fi
  done
  sleep 2
done
echo "not back after ~6 min (two failed tries fall back to the ChromeOS kernel; a long power-button press restarts)"; exit 2
