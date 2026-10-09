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

## Firewall: ufw on iptables-legacy (working since 2026-10-09)

- The ChromeOS kernel has legacy iptables (`CONFIG_IP_NF_IPTABLES=y`) but **no nftables**, and Arch's default
  `iptables` is the nft variant (`Could not fetch rule set generation id: Invalid argument`). Switched to
  `iptables-legacy` (`pacman -S --ask=4 iptables-legacy`).
- First attempt (2026-10-08): enabling Omarchy's ufw rules (deny in, LocalSend, LAN SSH, syncthing) **cut all traffic**,
  replies included. conntrack was fine (`nf_conntrack`/`xt_conntrack` load as modules). The real cause:
  `iptables-restore` is all-or-nothing, and ufw's stock files use matches/targets this kernel doesn't have, so the rule
  files failed to load while the default `DROP` policies were still set:
  - missing modules: `xt_LOG`/`nf_log_syslog` (logging), `ip6t_rt` (`-m rt`), `xt_hl` (`-m hl`), `xt_recent`,
    `xt_multiport`. Present: `xt_conntrack`, `xt_limit`, `xt_addrtype`, `xt_comment`, `xt_tcpudp`, `iptable_filter`,
    `ip6table_filter`.
  - `before6.rules` failed with `Extension rt revision 0 not supported`.
- Fix:
  - `ufw logging off` (no LOG target), which also drops the `-m limit` logging rules.
  - `fix-ufw-before6` (port/quigon/root/usr/local/bin): deletes the 4 `-m rt --rt-type 0 -j DROP` rules and strips
    `-m hl --hl-eq 255` from the NDP accept rules (they still accept the same ICMPv6 types, just without the hop-limit
    check). It keeps `/etc/ufw/before6.rules.quigon-orig`. `before6.rules` is a pacman backup file, so updates leave it
    alone and write a `.pacnew` instead. quigon-doctor (also run after each pacman transaction) re-applies the patch if
    `rt`/`hl` come back.
  - Tested with a detached `systemd-run` rollback (`sleep 90/120; ufw --force disable` unless a flag file in /run is
    removed). The first try timed out and rolled back on its own, which shows the safety net works. Then
    `systemctl restart ufw` (the boot path) → SSH, the bridge, and outgoing traffic all fine. A test HTTP server on 8765
    was unreachable from the LAN while 22 was reachable.
  - `ufw.service` enabled, `ENABLED=yes`.
- Limits on this kernel: no firewall logging, no `ufw limit` (needs `xt_recent`), and no multi-port rules like
  `allow 80,443/tcp` (needs `xt_multiport`). Use one rule per port, or ranges (`1000:2000/tcp` uses plain `--dport`). If
  a new rule makes ufw fail to load, `sudo ufw disable` at the keyboard restores the network. A kernel rebuild with
  NF_TABLES (+ those xt modules) would lift all of this.

