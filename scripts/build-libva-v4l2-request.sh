#!/bin/bash
# Hardware video decode for Chrome: the VA-API driver for V4L2 stateless decoders (sofus13's libva-v4l2_request 1.3,
# the source of Omarchy's libva-v4l2_request-avd package) with port/quigon/patches/libva-v4l2-request-mtk-mm21.patch,
# which makes it work on mtk-vcodec-dec (MT8189 decoder: stateless H.264/VP9/HEVC, MM21-only output):
#   - MM21 frames detiled to NV12 into dma-heap NV12 surfaces: on the GPU with Mesa/Panfrost (convert_gl.c, a GLES
#     shader on imported dma-bufs, ~2.9 ms per 4K frame, CPU idle: what ChromeOS does on MT8189), else on the CPU
#     (NEON, 4 threads, ~4 ms per 4K frame). V4L2R_GL_DETILE=0 forces the CPU path.
#   - CAPTURE buffers allocated non-coherent (cached) so the read-back is fast
#   - multi-planar CAPTURE QBUF/DQBUF (MM21 has two planes)
#   - H.264 DPB pic_num = PicNum (FrameNumWrap), without which references go wrong after frame_num wraps
# Installs /opt/quigon-gpu/va/v4l2_request_drv_video.so (outside pacman's files; the driver ABI follows libva's
# __vaDriverInit_1_xx, so rebuild after a libva driver-ABI bump - quigon-doctor checks it loads).
# Run as root on the device. Needs base-devel meson libdrm libva mesa/libglvnd headers (+ curl, patch).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ver=1.3
sha=3670a1712f9f0a5a61bd44a781eba81dd9b2e0fd8271417ca8a9fbbed9dccfe9
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/src.tar.gz" "https://github.com/sofus13/libva-v4l2_request/archive/refs/tags/$ver.tar.gz"
echo "$sha  $work/src.tar.gz" | sha256sum -c --quiet
tar xzf "$work/src.tar.gz" -C "$work"
cd "$work/libva-v4l2_request-$ver"
patch -p1 < "$here/../port/quigon/patches/libva-v4l2-request-mtk-mm21.patch"
meson setup --buildtype=release -Ddriverdir=/opt/quigon-gpu/va build >/dev/null
meson compile -C build
install -Dm755 build/src/v4l2_request_drv_video.so /opt/quigon-gpu/va/v4l2_request_drv_video.so
echo "installed /opt/quigon-gpu/va/v4l2_request_drv_video.so"
LIBVA_DRIVERS_PATH=/opt/quigon-gpu/va LIBVA_DRIVER_NAME=v4l2_request vainfo --display drm --device /dev/dri/renderD128 2>&1 |
  grep -E "VAProfile(H264|VP9|HEVC)" || { echo "vainfo lists no profiles"; exit 1; }
