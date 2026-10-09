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
| Audio, Bluetooth, battery | Audio card `mt8189_1019_rt5682s` probes; BT `hci0` up; battery reads (`sbs-battery`) — not tested further |
| Hyprland + Omarchy | **Works**: Omarchy 4.0.4 (official aarch64 `edge` packages), uwsm session on seat0, NetworkManager: [notes/desktop-20261008.md](notes/desktop-20261008.md) |
| GPU (Mali-G57 on kbase r54p1) | **Compositor on the GPU** via ChromeOS's own `libmali` r54p1 + a RELR patch + an EGL shim: [notes/gpu-20261008.md](notes/gpu-20261008.md). Apps still on llvmpipe |

## Layout

- `notes/` — dated bring-up logs.
- `scripts/bridge/` — LAN command bridge for driving the Chromebook from another machine (see [AGENTS.md](AGENTS.md)).
- `private/`, `artifacts/` — gitignored dumps (kernel partition, logs).
