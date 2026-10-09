# Dual-boot on the internal UFS drive, 2026-10-09

Omarchy moved from the USB stick into ChromeOS's spare C slots; ChromeOS (A/B) stays and stays readable.

## Partition changes (`/dev/sda`, 4 KiB sectors)

Backup of both GPT copies and `cgpt show` taken first (`private/gpt-backup-20261009/`, gitignored).

| # | Label | Before | After |
|---|---|---|---|
| 1 | STATE | 2165248 + 29048314 (110.8 GB) | 2165248 + 2097152 (**8 GiB**) |
| 6 | KERN-C | 32776 + 1 | 4262400 + 16384 (**64 MiB**, ChromeOS kernel type) |
| 7 | ROOT-C | 32777 + 1 | 4278784 + 26934778 (**102.7 GiB**, Linux data, ext4 `OMARCHY`) |

Everything else (KERN/ROOT-A/B, OEM, MINIOS-A/B, POWERWASH-DATA, EFI-SYSTEM, RWFW) untouched; new starts are 1 MiB aligned
and ROOT-C ends where MINIOS-B begins. The first 64 MiB of STATE were zeroed so ChromeOS rebuilds its (empty) stateful
partition on its next boot.

Tools: [`quigon-cgpt`](../port/quigon/root/usr/local/bin/quigon-cgpt) runs ChromeOS's own `cgpt` with ChromeOS's loader and
libs copied to `/opt/quigon-cros-tools` (`cgpt` needs only libuuid + glibc), so `/dev/sda3` can be unmounted for
`blockdev --rereadpt`. `crossystem` still runs via a chroot into ROOT-A.

## Contents and boot

- `rsync -aHAXx` of the running USB root (12 GB) to ROOT-C; KERN-C = byte copy of the USB stick's KERN-A (same
  devkey-signed ChromeOS kernel; `root=PARTUUID=%U/PARTNROFF=1` now resolves to ROOT-C).
- Swap: `/swapfile` 8 GiB on ROOT-C, `pri=10`, behind the 15.4G zram (`pri=100`) — the reminder from the zram work.
- Fail-safe first boot: KERN-C `priority=3 tries=1 successful=0` (KERN-A is 2). If the boot fails, the firmware falls back
  to ChromeOS; the USB stick still boots with Ctrl+U. [`quigon-boot-good.service`](../port/quigon/root/usr/local/libexec/quigon/boot-good)
  marks KERN-C `successful=1` with priority above A/B once the internal system is up.
- `crossystem dev_default_boot=disk` again (was usb); `dev_boot_usb=1` stays, so the stick is a rescue system.
