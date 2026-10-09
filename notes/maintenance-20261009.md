# Update safety, 2026-10-09

## quigon-doctor

[`quigon-doctor`](../port/quigon/root/usr/local/bin/quigon-doctor) checks every custom piece and repairs what is safe:
package config (Arch Linux ARM + Omarchy edge repos, ARM mirrorlist), ChromeOS modules for the running kernel, KERN-C
marked good, quigon services and drop-ins, zram, GPU files (libmali RELR copy, shims, chrome-lib, minigbm, private Zink
Mesa, Vulkan ICD + WSI layer, libc++), audio (alsa-card-profiles, pipewire-pulse, UCM2 profile), the battery panel patch,
and in the session: Hyprland on libmali, the bar, the desktop-file overrides for the GPU wrappers, the appended Hyprland
config blocks, hyprpm plugins, the speaker sink.

- `quigon-doctor` (check), `sudo quigon-doctor --fix` (repair), `--post-update` (pacman hook
  `zz-quigon-doctor.hook`, every transaction: non-session checks + repairs, critical notification if anything is left),
  `--guard-pacman` (path unit).
- `quigon-pacman-guard.path` watches `/etc/pacman.conf` and `/etc/pacman.d/mirrorlist`; if either loses Arch Linux ARM it
  restores `/etc/quigon/pacman.conf.good` / `mirrorlist.good` (the replaced file is kept alongside) and notifies. Reason:
  `omarchy-refresh-pacman` (and anything Omarchy migrations run that calls it) copies Omarchy's **x86** pacman.conf and
  mirrorlist over ARM's; `omarchy-update` itself doesn't touch them.
- First run: 36 ok, then the one failure turned out to be a platform limit:

## hypr-tab-drag doesn't work on ARM

`hyprctl plugin load …/tab-drag.so` → `plugin crashed/threw in main: [tab-drag] could not hook the compositor functions`.
It uses Hyprland function hooks (runtime code patching), which fail on aarch64; `hyprpm` still prints "Loaded tab-drag".
hypr-momentum loads fine (no hooks). Fix would be porting tab-drag to Hyprland event/config APIs.
