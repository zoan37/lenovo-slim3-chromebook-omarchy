# Omarchy on Lenovo IdeaPad Slim 3 Chromebook (Kompanio 540)

Native Arch Linux ARM and Omarchy on the 2026 **Lenovo IdeaPad Slim 3 Chromebook** (model label 14M891x):
MediaTek Kompanio 540 (**MT8189**, 4× Cortex-A78 + 4× A55), Mali-G57 MC2, 8 GB LPDDR5X, 128 GB UFS,
1920×1200 eDP. ChromeOS board `skywalker`, variant **quigon**, which boots the `google,obiwan` device tree.

There is no UEFI firmware (MrChromebox) for MediaTek Chromebooks, so everything boots through ChromeOS's own
bootloader (depthcharge) in developer mode, from kernel partitions signed with the developer keys. ChromeOS stays on
the internal drive. Experimental device port, not an installer.

## Two kernels, one Omarchy

**I use the mainline (custom) kernel day to day**: it's this Chromebook's default boot, and everything below the
"Mainline kernel" column is what that daily setup does. The ChromeOS kernel stays installed only as the automatic
fallback.

The same Omarchy install (ROOT-C on the internal drive) runs on either of two kernels:

| | **Mainline kernel** (default since 2026-10-10) | **ChromeOS kernel** (the first approach, now the fallback) |
|---|---|---|
| What it is | linux-next + the MT8189 series posted upstream + this repo's patches ([`port/quigon/patches/mainline-*`](port/quigon/patches)), board DTS in [`port/quigon/mainline/`](port/quigon/mainline) | ChromeOS's own `chromeos-6.6` kernel from the device, re-signed with the devkeys |
| Boots from | KERN-B; two failed boots in a row and the firmware falls back to KERN-C | KERN-C |
| GPU | **Stock Mesa on Panfrost** (Mali-G57), no wrappers | ChromeOS's closed `libmali`, bridged to desktop Linux with an EGL shim, minigbm, Zink and per-app wrappers |
| Suspend | Real s2idle through the SPM (~0.1 W asleep); lid/keyboard/RTC wake | s2idle |
| External displays | HDMI (up to 4K30, hotplug) and USB-C DisplayPort (2560×1080@60 / 4K30, 65 W PD charging), both with audio | not set up |
| Video | H.264/VP9 decode (VA-API, GPU detile) and H.264 encode (V4L2 M2M) | H.264/VP9 decode (VA-API, CPU detile) |
| Kernel features | memory cgroups (systemd-oomd), disk swap, nftables, firewall logging, VT console, GSC TPM | none of those (ChromeOS config) |
| Audio, Wi-Fi, BT, input, camera, battery | work | work |
| Notes | [notes/mainline-20261009.md](notes/mainline-20261009.md) | [notes/usb-boot-20261008.md](notes/usb-boot-20261008.md), [notes/gpu-20261008.md](notes/gpu-20261008.md) |

**Why two:** in October 2026 MT8189 has no mainline board support (only parts of it are in review), so the port
started on the vendor kernel, as the [Moto G Power 2025 port](https://github.com/zoan37/moto-g-power-2025-omarchy)
did: keep the vendor kernel, replace the userspace. That worked (Hyprland, Chrome and Electron on the GPU through
libmali shims), but the closed GPU stack can't be redistributed and the ChromeOS kernel config lacks desktop
features. The mainline kernel (started 2026-10-09) replaces all of that with stock Mesa and an ordinary kernel
config, and became the default once it did everything the ChromeOS kernel did.

Omarchy's own switches keep working under both: `quigon-mainline.service` masks the libmali setup on mainline, and
`quigon-doctor` checks whichever kernel is running.

## Status (mainline kernel)

| Area | State |
|---|---|
| Display | eDP 1920×1200@60 (DVO/eDP ported from ChromeOS), hardware cursor; HDMI via the ITE IT61620 bridge; USB-C DP (mtk_dp_v2 from ChromeOS) |
| GPU | Panfrost, within ~4% of libmali on shader work; Ghostty on a private Panfrost Mesa build (GL 4.3) |
| Suspend | s2idle with the SPM; 20/20 + 10/10 + 10/10 stress cycles; displays, Wi-Fi, audio come back |
| Audio | Speakers, headphones, internal + headset mic (UCM2 profile from ChromeOS's quigon config), HDMI and DisplayPort |
| Video | H.264/VP9 hardware decode in Chrome (bit-exact), H.264 encode for ffmpeg/GStreamer; no HEVC (the single-core decoder interface isn't implemented, ChromeOS's kernel included) |
| Wi-Fi, Bluetooth | MT7922 on PCIe (L1.2 while awake, dropped across s2idle where it hangs the SoC), Bluetooth; USB Wi-Fi dongle as backup |
| Input | Keyboard (top row mapped), touchpad with ChromeOS's palm rejection ported ([notes](notes/touchpad-palm-20261009.md)), touchscreen, keyboard backlight |
| Camera | UVC webcam (720p), works in Chrome |
| Power | ~1.3–1.9 W idle on battery (screen dim, nothing plugged in), ~7 W under full load, 83 °C max |
| Firewall | ufw |
| Debug | SuzyQ (home-made): GSC/AP/EC consoles, kernel log on the AP UART, CCD open, remote reset ([notes](notes/suzyq-20261010.md)) |

Day-to-day health check: `quigon-doctor`.

## Kernel tools

- `quigon-kernel status | install | restore [previous] | off` (on the Chromebook): the default mainline kernel in
  KERN-B, the previous one kept as the rollback.
- [`scripts/mainline-default.sh <tag>`](scripts/mainline-default.sh): build the kernel tree on a build host, install
  it as the default (own module directory per default kernel).
- [`scripts/mainline-full.sh <tag>`](scripts/mainline-full.sh): boot a test kernel once; the default comes back after.
- [`scripts/sleepstress.sh`](scripts/sleepstress.sh), [`scripts/test-video-decode.sh`](scripts/test-video-decode.sh):
  regression tests. [`scripts/suzyq.sh`](scripts/suzyq.sh): debug consoles and remote reset.

## Layout

- `notes/` — dated bring-up logs (start with [recon](notes/recon-20261008.md), then
  [USB boot](notes/usb-boot-20261008.md), [dual boot](notes/internal-dualboot-20261009.md),
  [desktop](notes/desktop-20261008.md), [mainline](notes/mainline-20261009.md)).
- `port/quigon/` — the files installed on the Chromebook (`root/`, `user/`), kernel patches, mainline DTS.
- `scripts/` — build, boot and test scripts; `scripts/bridge/` drives the Chromebook from another machine
  (see [AGENTS.md](AGENTS.md)).
- `private/`, `artifacts/` — gitignored dumps (firmware, kernel partitions, logs).

## To do

- Kernel updates: rebase the patches onto newer kernels as MT8189 support lands upstream; send the generic fixes
  upstream (the mmap error-path fix, the MT6359 RTC year, the mediatek-drm CRTC route, the IT61620 audio format).
- Why PCIe L1.2 hangs s2idle on mainline (worked around: L1.2 only while awake).
- Optional: disk swap on ROOT-C behind zram, systemd-oomd, an 80% battery charge cap (`CHARGER_CROS_CONTROL`).
- Unpin Quickshell (`IgnorePkg`, held at 0.3.1) once a release fixes quickshell#1230 / omarchy#14588.
- Port hypr-tab-drag off Hyprland function hooks (they fail on aarch64).
