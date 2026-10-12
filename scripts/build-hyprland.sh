#!/bin/bash
# build-hyprland.sh [chroot-dir]: build quigon's Hyprland package (port/quigon/pkgbuilds/hyprland: Omarchy's PKGBUILD,
# its own patch, plus quigon-map-size-hold.patch) on the build host, in an Arch Linux ARM chroot that uses the
# Chromebook's pacman.conf (same repos, so the same library versions), and copy the package to ./artifacts/.
#
#   QUIGON_BUILD_HOST=user@build-host scripts/build-hyprland.sh            # chroot: ~/quigon-mesa/alarm-root
#   scp artifacts/hyprland-<ver>.pkg.tar.* root@<chromebook>:/tmp/ && ssh root@<chromebook> pacman -U /tmp/hyprland-<ver>.pkg.tar.*
#
# When Omarchy publishes a new Hyprland (quigon-doctor says so): take its PKGBUILD from omacom/omarchy-pkgs
# (pkgbuilds/hyprland), keep pkgrel=<theirs>.1 and the quigon-map-size-hold.patch lines, check the patch still applies
# (patch --fuzz=0), rebuild and install. Rollback: pacman -U /root/pkg-backup/hyprland-*.pkg.tar.zst.
set -euo pipefail
BH=${QUIGON_BUILD_HOST:?set QUIGON_BUILD_HOST=user@build-host}
R=${1:-quigon-mesa/alarm-root}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/../artifacts"
tar -C "$here/../port/quigon/pkgbuilds" -czf - hyprland | ssh "$BH" "set -e
  cd ~/\$(dirname $R); r=\$(basename $R)
  mountpoint -q \$r || sudo mount --bind \$r \$r   # pacman needs the chroot to be a mountpoint
  sudo rm -rf \$r/build/hyprland; sudo mkdir -p \$r/build; sudo tar xzf - -C \$r/build
  sudo arch-chroot \$r bash -c '
    id builder >/dev/null 2>&1 || useradd -m builder
    cd /build/hyprland && source ./PKGBUILD
    deps=\$(printf \"%s\n\" \"\${depends[@]}\" \"\${makedepends[@]}\" | grep -v \"\\.so\" | sort -u)
    pacman -Syu --needed --noconfirm base-devel \$deps >/build/deps.log 2>&1 || { tail -5 /build/deps.log; exit 1; }
    chown -R builder /build/hyprland
    su builder -c \"MAKEFLAGS=-j\$(nproc) makepkg -f --noconfirm\" >/build/makepkg.log 2>&1 || { tail -20 /build/makepkg.log; exit 1; }'"
scp "$BH:$R/build/hyprland/hyprland-[0-9]*.pkg.tar.*" "$here/../artifacts/"
ls -la "$here"/../artifacts/hyprland-[0-9]*.pkg.tar.*
