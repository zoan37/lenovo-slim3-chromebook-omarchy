#!/bin/sh
# qblk <step...>: hang-proof log for the test kernel. quigon.blklog=<4 KiB block in sda7> names a preallocated
# 4 MiB file on Omarchy's root (/var/lib/quigon/mainline-blklog, one extent; mainline-log prints it). Each call
# writes the step name, the kernel log and the wpa/dhcp logs there through the raw block device and flushes it,
# so a hard freeze that wipes pstore still leaves the last step on disk. Written only if the region holds zeros or
# an earlier QBLK header, so a stale offset can't hit filesystem data.
# qblk -bg <label>: keep doing it every second in the background (prints the PID; kill it to stop).
off=$(sed -n 's/.*quigon\.blklog=\([0-9]*\).*/\1/p' /proc/cmdline)
[ -n "$off" ] && [ -b /dev/sda7 ] || exit 0
if [ "$1" = -bg ]; then
  shift; ( while :; do "$0" "periodic ($*)"; sleep 1; done ) >/dev/null 2>&1 & echo $!; exit 0
fi
head=$(dd if=/dev/sda7 bs=4096 skip=$off count=1 2>/dev/null | head -c 4 | tr -d '\0')
if [ -n "$head" ] && [ "$head" != QBLK ]; then
  echo "QM: blklog: region not empty/QBLK ('$head'), not writing" > /dev/kmsg; exit 1
fi
(
  flock 9
  n=$(($(cat /tmp/blkseq 2>/dev/null || echo 0)+1)); echo $n > /tmp/blkseq
  { echo "QBLK seq=$n step=$* uptime=$(cut -d' ' -f1 /proc/uptime)"; dmesg
    [ -f /tmp/wpa.log ] && { echo "== wpa_supplicant:"; grep -v -i -E 'psk|passphrase|ssid' /tmp/wpa.log | tail -40; }
    [ -f /tmp/dhcp.log ] && { echo "== udhcpc:"; tail -10 /tmp/dhcp.log; }; } > /tmp/blk
  truncate -s 4194304 /tmp/blk
  dd if=/tmp/blk of=/dev/sda7 bs=4096 seek=$off count=1024 conv=notrunc,fsync 2>/dev/null
) 9>/tmp/blk.lock
