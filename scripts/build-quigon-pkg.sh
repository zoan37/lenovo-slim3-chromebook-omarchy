#!/bin/bash
# build-quigon-pkg.sh <name> [chroot-dir]: build one of quigon's patched packages (port/quigon/pkgbuilds/<name>: Omarchy's
# PKGBUILD and files plus our patch; hyprland, quickshell) on the build host, in an Arch Linux ARM chroot that uses the
# Chromebook's pacman.conf (same repos, so the same library versions), and copy the package to ./artifacts/.
#
#   QUIGON_BUILD_HOST=user@build-host scripts/build-quigon-pkg.sh <name>   # chroot: ~/quigon-mesa/alarm-root
#   scp artifacts/<name>-<ver>.pkg.tar.* root@<chromebook>:/tmp/ && ssh root@<chromebook> pacman -U /tmp/<name>-<ver>.pkg.tar.*
#
# When Omarchy publishes a new version (quigon-doctor says so for hyprland): take its PKGBUILD and files from
# omacom/omarchy-pkgs (pkgbuilds/<name>), keep pkgrel=<theirs>.1 and our patch lines, check our patch still applies
# (patch --fuzz=0), rebuild and install. Rollback: pacman -U /root/pkg-backup/<name>-*.pkg.tar.zst.
set -euo pipefail
BH=${QUIGON_BUILD_HOST:?set QUIGON_BUILD_HOST=user@build-host}
N=${1:?package name (port/quigon/pkgbuilds/<name>)}
R=${2:-quigon-mesa/alarm-root}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/../artifacts"
tar -C "$here/../port/quigon/pkgbuilds" -czf - "$N" | ssh "$BH" "set -e
  cd ~/\$(dirname $R); r=\$(basename $R)
  mountpoint -q \$r || sudo mount --bind \$r \$r   # pacman needs the chroot to be a mountpoint
  sudo rm -rf \$r/build/$N; sudo mkdir -p \$r/build; sudo tar xzf - -C \$r/build
  sudo arch-chroot \$r bash -c '
    id builder >/dev/null 2>&1 || useradd -m builder
    cd /build/$N && source ./PKGBUILD
    deps=\$(printf \"%s\n\" \"\${depends[@]}\" \"\${makedepends[@]}\" | grep -v \"\\.so\" | sort -u)
    pacman -Syu --needed --noconfirm base-devel \$deps >/build/deps.log 2>&1 || { tail -5 /build/deps.log; exit 1; }
    chown -R builder /build/$N
    su builder -c \"MAKEFLAGS=-j\$(nproc) makepkg -f --noconfirm\" >/build/makepkg.log 2>&1 || { tail -20 /build/makepkg.log; exit 1; }'"
scp "$BH:$R/build/$N/$N-[0-9]*.pkg.tar.*" "$here/../artifacts/"
ls -la "$here"/../artifacts/"$N"-[0-9]*.pkg.tar.*
