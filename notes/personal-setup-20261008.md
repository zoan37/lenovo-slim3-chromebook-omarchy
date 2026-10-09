# Cross-machine Omarchy settings, apps, and gotchas, 2026-10-08

Ported from omarchy-setup (`hyprland-shell-tweaks.md`, `new-machine-checklist.md`, `hyprpm-notes.md`).

## Applied

- `input.lua`: `altwin:swap_lalt_lwin` (left Alt ↔ the launcher/Super key, macOS-style), natural scroll,
  `disable_while_typing = false`, 3-finger horizontal workspace swipe (distance 150, cancel 0.1, force speed 2).
- `looknfeel.lua`: resize on border, grab area 15, hover icon.
- `bindings.lua`: group tab reorder (SUPER+CTRL+SHIFT+←/→), SUPER+A select all (`send_shortcut_once` helper),
  SUPER+SHIFT+S screenshot (with `hl.unbind`, replaces the Google Maps webapp bind).
- Bar: clock `ddd d MMM h:mm AP`, `~/.config/omarchy/shell.toml` `[font] base-size = 12`.
- `monitors.lua`: left at Omarchy's automatic scale 1.25 for the 14" 1920×1200 panel.
- hyprpm plugins hypr-momentum + hypr-tab-drag, `o.exec_on_start("hyprpm reload -n")` in `autostart.lua`.
- Ghostty default terminal (`omarchy-default-terminal ghostty`), `~/.config/ghostty/local.conf` `font-size = 11`
  included from `config`. Ghostty needs desktop GL, so it renders on llvmpipe (libmali is GLES-only).
- Google Chrome (`google-chrome` 155 from Omarchy's aarch64 repo), default browser,
  `chrome-flags.conf`: `--enable-features=TouchpadOverscrollHistoryNavigation` only (no Vulkan/VA-API here).
- Bar-clock refresh sleep hook, git identity, syncthing installed + enabled (not configured).

## Gotchas

- **The Arch Linux ARM tarball has no `base-devel`.** hyprpm then fails in "Building Hyprland" with
  `CMake was unable to find a build program corresponding to "Unix Makefiles"` and reports `Headers missing`.
  Install `base-devel cmake cpio pkgconf meson ninja hyprpm` first.
- hyprpm elevates every write with `sudo`; non-interactively it was run with a temporary
  `/etc/sudoers.d/99-tmp-hyprpm` NOPASSWD rule, removed right after.

## Firewall: not enabled (broken on this kernel, revisit)

- The ChromeOS kernel has legacy iptables (`CONFIG_IP_NF_IPTABLES=y`) but **no nftables**, and Arch's default
  `iptables` is the nft variant (`Could not fetch rule set generation id: Invalid argument`). Switched to
  `iptables-legacy` (`pacman -S --ask=4 iptables-legacy`).
- With Omarchy's ufw rules (deny in, LocalSend, LAN SSH, syncthing) enabled, **all traffic stopped**, including
  replies to outgoing connections, so SSH and the bridge both died. Most likely the
  `-m conntrack --ctstate RELATED,ESTABLISHED` rules don't work: `xt_conntrack`/`nf_conntrack` are modules
  (`CONFIG_NETFILTER_XT_MATCH_CONNTRACK=m`) and either aren't in the copied module tree or didn't load. Recovered with
  `sudo ufw disable` at the keyboard; `ufw.service` disabled. Next time: check `modprobe xt_conntrack`, test the rules
  with a timed auto-revert (`ufw enable; sleep 60; ufw disable` in a detached unit) before leaving it on.
