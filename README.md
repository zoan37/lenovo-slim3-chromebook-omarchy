# Omarchy on Lenovo IdeaPad Slim 3 Chromebook (Kompanio 540)

Native Arch Linux ARM and Omarchy on the 2026 **Lenovo IdeaPad Slim 3 Chromebook** (model label 14M891x):
MediaTek Kompanio 540 (**MT8189**, 4× Cortex-A78 + 4× A55), Mali-G57 MC2, 8 GB LPDDR5X, 128 GB UFS,
1920×1200 eDP. ChromeOS board `skywalker`, variant **quigon**, which boots the `google,obiwan` device tree.

There is no UEFI firmware (MrChromebox) for MediaTek Chromebooks and no mainline board support for the MT8189
yet (October 2026: only the clock/reset series is in review). So the plan follows the
[Moto G Power 2025 port](https://github.com/zoan37/moto-g-power-2025-omarchy): keep the vendor kernel, replace
the userspace. Here the vendor kernel is ChromeOS's own `chromeos-6.6` kernel, re-signed with the developer
keys and booted from USB in developer mode, so ChromeOS stays on the internal drive.

Experimental device port, not an installer.

## Status

| Stage | State |
|---|---|
| Developer mode | Done 2026-10-08 |
| Recon (kernel, GPU, Wi-Fi, storage) | Done: [notes/recon-20261008.md](notes/recon-20261008.md) |
| Arch Linux ARM booting from USB on the ChromeOS kernel | **Works** (2026-10-08, first try): systemd `running`, no failed units, Wi-Fi + DHCP, SSH, bridge. [notes/usb-boot-20261008.md](notes/usb-boot-20261008.md) |
| Input | Detected: Elan touchpad, cros_ec keyboard + buttons, tc3408 touchscreen, headset/HDMI/DP jacks |
| Display (mediatek-drm KMS) | Hyprland drives eDP-1 at 1920×1200@60 |
| Audio | **Works**: speaker, headphones, internal + headset mic via a UCM2 profile converted from ChromeOS's quigon config ([notes/input-audio-20261009.md](notes/input-audio-20261009.md)); HDMI/DP audio not yet |
| Keyboard top row | Fullscreen/overview/lock keys bound; brightness, volume, kbd backlight stock |
| Touchpad palm rejection | ChromeOS's palm classifier ported as a uinput filter ([notes/touchpad-palm-20261009.md](notes/touchpad-palm-20261009.md)) |
| Bluetooth, battery, suspend | BT works (scan); battery panel patched; s2idle suspend/resume passes the RTC-wake test |
| Touchscreen, webcam | Both work out of the box |
| Firewall | **ufw on** (iptables-legacy; IPv6 rules patched, logging off: kernel lacks nftables, `xt_LOG`, `xt_hl`, `ip6t_rt`): [notes/personal-setup-20261008.md](notes/personal-setup-20261008.md#firewall-ufw-on-iptables-legacy-working-since-2026-10-09) |
| Hardware video decode | Not usable from Linux Chrome (decoder outputs MediaTek MM21 only) |
| Hyprland + Omarchy | **Works**: Omarchy 4.0.4 (official aarch64 `edge` packages), uwsm session on seat0, NetworkManager: [notes/desktop-20261008.md](notes/desktop-20261008.md) |
| GPU (Mali-G57 on kbase r54p1) | **On the GPU**: Hyprland, Chrome and every Electron app (auto-routed by `quigon-electron-sync`) on ChromeOS's own `libmali` GLES (RELR patch + EGL shim, + minigbm for Chromium); GTK 4 apps on libmali Vulkan via a patched ARM vulkan-wsi-layer; the Omarchy bar on libmali Vulkan (Qt Quick RHI, software fallback); other OpenGL apps via Zink; Ghostty via a patched private Zink. [notes/gpu-20261008.md](notes/gpu-20261008.md) |

## Layout

- `notes/` — dated bring-up logs.
- `scripts/bridge/` — LAN command bridge for driving the Chromebook from another machine (see [AGENTS.md](AGENTS.md)).
- `private/`, `artifacts/` — gitignored dumps (kernel partition, logs).

## To do

- **The real fix: mainline kernel + open GPU driver (project).** Everything GPU-related here bridges ChromeOS's
  closed `libmali` to desktop Linux (EGL shim, minigbm, Zink, per-app wrappers, the bar on software). With a mainline
  kernel that knows MT8189 plus Panfrost for the Mali-G57 (Mesa's Panfrost is already conformant on G57, e.g. MT8195),
  stock Arch packages would use the GPU everywhere with no wrappers. The same kernel would bring disk swap, MEMCG/oomd,
  nftables and firewall logging. Status as of 2026-10: Collabora/MediaTek are upstreaming MT8189 piece by piece
  (pinctrl; base clocks at [v6, 2026-09](https://ratatoskr.run/linux-arm-kernel/2026/09/17515358/t), with
  multimedia/GPU clocks split out for later; MediaTek's Genio 520/720 IoT boards use the same SoC family). Velvet OS
  tracks Skywalker mainlining in [imagebuilder#448](https://github.com/velvet-os/imagebuilder/issues/448).
  Plan: follow the series, boot a mainline (or linux-next + series) kernel from USB with a quigon/obiwan DTS, signed
  like today's kernel, and report what works upstream. That's also the path to Omarchy supporting ARM Chromebooks
  officially (Omarchy's aarch64 `edge` packages already run here; the closed libmali stack can't be redistributed).
- **Rebuild the ChromeOS kernel** (`chromeos-6.6`, obiwan/quigon config) with: `CONFIG_DISK_BASED_SWAP` (disk swap is
  refused without it; then add a swap file on ROOT-C behind zram), `CONFIG_MEMCG` (systemd-oomd), `CONFIG_NF_TABLES`
  + `xt_LOG`/`xt_recent`/`xt_multiport` (full ufw: logging, `limit`, port lists), `CONFIG_VT`/fbcon (boot console), maybe `CONFIG_HIBERNATION`. Sign with the devkeys like today's kernel.
- Unpin Quickshell (`IgnorePkg`, held at 0.3.1) once a release fixes quickshell#1230 / omarchy#14588.
- Port hypr-tab-drag off Hyprland function hooks (they fail on aarch64).
- HDMI/DisplayPort audio (UCM devices left out until tested with a display attached).
- Syncthing folders; hardware video decode (MediaTek vcodec) for Chrome; re-sync script for ChromeOS kernel/modules/firmware/
  libmali after ChromeOS updates; backup image of the USB stick.
