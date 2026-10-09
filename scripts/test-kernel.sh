#!/bin/bash
# test-kernel.sh <kernel-partition-image> [cmdline-file]
#   Boot-once test slot: signs a kernel blob with the devkeys, writes it to KERN-B (ChromeOS's spare A/B slot; the
#   original is backed up in /root/kern-backup/kern-b-chromeos.bin) and marks it priority 4, tries 1, not successful.
#   The next boot uses it exactly once; nothing marks it good, so the boot after falls back to KERN-C (Omarchy).
#   A test kernel that hangs before its watchdog/panic=N kicks in needs a long press of the power button, then
#   Omarchy comes back. Logs of a crashed test boot: /sys/fs/pstore after the warm reboot (ramoops at 0xffec5000,
#   1 MiB, set up by the firmware for any kernel).
#   <kernel-partition-image> is anything futility can repack (--oldblob): an existing vblock'd kernel partition, or
#   use --vmlinuz <FIT image> to pack a new one.
#   test-kernel.sh --status | --disarm | --restore-chromeos
# Run as root on the device.
set -euo pipefail
K=/usr/local/share/quigon/devkeys
B=/root/kern-backup
cgpt() { quigon-cgpt "$@"; }
status() { for i in 2 4 6; do echo "$(cgpt show -i $i -l /dev/sda): prio=$(cgpt show -i $i -P /dev/sda) tries=$(cgpt show -i $i -T /dev/sda) ok=$(cgpt show -i $i -S /dev/sda)"; done; }
case ${1:-} in
  --status) status; grep -o "quigon.test=[^ ]*" /proc/cmdline || echo "running: normal kernel"; exit 0 ;;
  --disarm) cgpt add -i 4 -P 0 -T 0 -S 0 /dev/sda; status; exit 0 ;;
  --restore-chromeos) dd if=$B/kern-b-chromeos.bin of=/dev/sda4 bs=1M conv=fsync status=none; cgpt add -i 4 -P 1 -T 0 -S 1 /dev/sda; status; exit 0 ;;
esac
install -d -m700 $B
[[ -f $B/kern-b-chromeos.bin ]] || dd if=/dev/sda4 of=$B/kern-b-chromeos.bin bs=1M status=none
out=$B/kern-test.bin
if [[ ${1:-} == --vmlinuz ]]; then
  fit=${2:?FIT image}; cfg=${3:?cmdline file}
  printf 'fake' > $B/bootloader.bin   # depthcharge ignores it on arm64
  futility vbutil_kernel --pack $out --keyblock $K/kernel.keyblock --signprivate $K/kernel_data_key.vbprivk \
    --version 1 --config "$cfg" --bootloader $B/bootloader.bin --vmlinuz "$fit" --arch aarch64
else
  blob=${1:?kernel partition image}; cfg=${2:?cmdline file}
  futility vbutil_kernel --repack $out --oldblob "$blob" --keyblock $K/kernel.keyblock \
    --signprivate $K/kernel_data_key.vbprivk --config "$cfg"
fi
size=$(stat -c %s $out); (( size <= 32 * 1024 * 1024 )) || { echo "test kernel is $size bytes, KERN-B holds 32 MiB"; exit 1; }
futility vbutil_kernel --verify $out >/dev/null
dd if=$out of=/dev/sda4 bs=1M conv=fsync status=none
cgpt add -i 4 -P 4 -T 1 -S 0 /dev/sda
echo "armed: next boot runs the test kernel once ($(numfmt --to=iec $size)); the one after falls back to KERN-C"
# The reboot into the test kernel is intentional: don't let quigon-gpu-guard count this (possibly short) boot as an
# unconfirmed GPU boot, or a few quick test rounds switch the GPU desktop off.
rm -f /var/lib/quigon/gpu-pending
status
