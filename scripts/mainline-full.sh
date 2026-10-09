#!/bin/bash
# mainline-full.sh <tag> [extra cmdline]: boot the Omarchy install (ROOT-C) once on the mainline kernel built on the
# build host (QUIGON_BUILD_HOST, ~/quigon-kernel/$BUILD_DIR, default build-s1; build Image, modules and dtbs first).
#   1. install that build's modules into the Chromebook's /usr/lib/modules/<release> (next to the ChromeOS kernel's),
#   2. pack Image + DTB (default mt8189-quigon-all) as a FIT and arm the boot-once slot (mainline-pack.sh FULL=1),
#   3. reboot and wait for the system to come back on either address (the USB Wi-Fi dongle, when plugged in, gets its
#      own lease). The reboot after that is back on the ChromeOS kernel.
# The Chromebook can be running either kernel: Omarchy's tools (quigon-test-kernel, cgpt) work under both.
set -euo pipefail
tag=${1:?tag}; extra=${2:-}
here=$(cd "$(dirname "$0")" && pwd)
BH=${QUIGON_BUILD_HOST:?set QUIGON_BUILD_HOST=user@build-host}; BD=${BUILD_DIR:-build-s1}
addrs=${QUIGON_ADDRS:-192.168.0.22 192.168.0.27}
T=(-o ConnectTimeout=4 -o BatchMode=yes)
cb=""; for ip in $addrs; do timeout 6 ssh "${T[@]}" root@$ip true 2>/dev/null && { cb=root@$ip; break; }; done
[[ -n $cb ]] || { echo "Chromebook not reachable on $addrs"; exit 1; }
V=$(ssh "$BH" "cat ~/quigon-kernel/$BD/include/config/kernel.release")
echo "installing modules for $V on $cb"
ssh "$BH" "set -e; cd ~/quigon-kernel; rm -rf modroot-$BD; make -s ARCH=arm64 O=\$HOME/quigon-kernel/$BD -C linux-next modules_install INSTALL_MOD_PATH=\$HOME/quigon-kernel/modroot-$BD INSTALL_MOD_STRIP=1 < /dev/null; cd modroot-$BD/lib/modules; rm -f $V/build $V/source; tar czf - $V" |
  ssh "${T[@]}" "$cb" "set -e; rm -rf /usr/lib/modules/.$V.new; mkdir /usr/lib/modules/.$V.new; tar xzf - -C /usr/lib/modules/.$V.new; rm -rf /usr/lib/modules/$V; mv /usr/lib/modules/.$V.new/$V /usr/lib/modules/$V; rmdir /usr/lib/modules/.$V.new"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/arch/arm64/boot/dts/mediatek"
scp -q "$BH:quigon-kernel/$BD/arch/arm64/boot/Image" "$W/arch/arm64/boot/"
scp -q "$BH:quigon-kernel/$BD/arch/arm64/boot/dts/mediatek/${DTB:-mt8189-quigon-all}.dtb" "$W/arch/arm64/boot/dts/mediatek/"
QUIGON_HOST=$cb FULL=1 DTB=${DTB:-mt8189-quigon-all} "$here/mainline-pack.sh" "$W" "$tag" "$extra"
ssh "${T[@]}" "$cb" 'sync; systemctl reboot' 2>/dev/null || true
sleep 25
for i in $(seq 1 60); do
  for ip in $addrs; do
    if c=$(timeout 6 ssh "${T[@]}" root@$ip 'uname -r; grep -o "quigon.test=[^ ]*" /proc/cmdline' 2>/dev/null); then
      echo "up at $ip after ~$((25 + i * 6)) s: $(tr '\n' ' ' <<<"$c")"; exit 0
    fi
  done
  sleep 2
done
echo "not back after ~6 min (hung? a power-button press brings back the ChromeOS kernel)"; exit 2
