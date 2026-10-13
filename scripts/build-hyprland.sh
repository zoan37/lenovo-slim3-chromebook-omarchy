#!/bin/bash
# build-hyprland.sh [chroot-dir]: quigon's Hyprland package (port/quigon/pkgbuilds/hyprland), see build-quigon-pkg.sh
exec "$(dirname "$0")/build-quigon-pkg.sh" hyprland "$@"
