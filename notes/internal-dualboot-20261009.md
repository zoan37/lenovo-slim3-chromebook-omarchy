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

## First boot from the internal drive

- Booted on the first try; `quigon-boot-good` marked KERN-C `priority=3 tries=0 successful=1` (KERN-A stays 2).
- **Disk swap is impossible on this kernel**: `swapon` returns `EINVAL` (no kernel message) for a fallocated file, a
  dd-written file, and a file behind a `--direct-io` loop device. The ChromeOS kernel has `# CONFIG_DISK_BASED_SWAP is not
  set`, a ChromeOS option that limits swap to zram. Also `# CONFIG_HIBERNATION is not set`, so no hibernation either.
  Swapfile and its fstab line removed. Disk swap needs a rebuilt kernel (`chromeos-6.6` + `CONFIG_DISK_BASED_SWAP=y`).
- **Quickshell (Omarchy bar) crash loop** after the reboot: with apps defaulting to Zink, and then with no Mesa override
  at all, Qt Quick crashed in Mesa's Wayland EGL `swapBuffers` → `dri2_query_image` (Mesa picked the mediatek display
  node as a GPU). It worked before only because the pre-reboot session still had the old llvmpipe variables. The bar is
  started by Hyprland, so it inherits the compositor unit's environment (`gpu.env`), not later `systemctl --user
  set-environment` changes. Fix: `gpu.env` now also sets `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe` (libmali ignores
  them; Hyprland's children get llvmpipe), the launcher exports the llvmpipe variables for apps again, and Zink is opt-in
  per app with [`quigon-zink`](../port/quigon/root/usr/local/bin/quigon-zink). Crashed shells leave
  `/usr/bin/quickshell` crash-handler processes under `systemd --user`; `pkill -x quickshell` before restarting.
