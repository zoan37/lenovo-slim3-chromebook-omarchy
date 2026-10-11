#!/bin/bash
# build-mesa-panfrost.sh: private Mesa (Panfrost only) for Ghostty on the Mali-G57 under the mainline kernel.
#
# Ghostty needs GL 4.3 and reads an SSBO in its vertex shader. Stock Panfrost reports 0 vertex-stage SSBOs, so the
# link fails ("Too many vertex shader storage blocks (1/0)"). port/quigon/patches/mesa-panfrost-ro-vertex-ssbo.patch
# adds PAN_RO_VERTEX_SSBO=1: vertex shaders get SSBOs, and any vertex SSBO write/atomic is dropped (read-only).
# The GL version itself is raised by the wrapper (MESA_GL_VERSION_OVERRIDE=4.3 MESA_GLSL_VERSION_OVERRIDE=430),
# see port/quigon/root/usr/local/bin/quigon-ghostty.
#
# Output: $OUT, a tarball with paths relative to / containing $PREFIX (default /opt/quigon-gpu/mesa-panfrost):
# libEGL_mesa, libgbm, libgallium, the GBM backend and share/glvnd/egl_vendor.d/50_mesa.json. Install with
#   tar -C / -xzf mesa-panfrost-26.2.4-aarch64.tar.gz
# It links against the system's libdrm/wayland/libglvnd/expat/zlib/zstd/libelf (no LLVM at runtime).
#
# Run as root on an Arch Linux ARM aarch64 system: the Chromebook itself, or an ALARM chroot on a faster aarch64
# host (build in the same package set as the target so the libraries match). For a chroot:
#   sudo bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C alarm-root && sudo mount --bind alarm-root alarm-root
#   sudo cp /etc/resolv.conf alarm-root/etc/ && sudo arch-chroot alarm-root   # then pacman-key --init,
#   pacman-key --populate archlinuxarm, pacman -Syu; copy this repo in and run the script with
#   PACMAN_FLAGS=--disable-sandbox if pacman complains about Landlock.
#
# Env: WORK (build dir, default /root/mesa-panfrost), OUT (tarball path), JOBS, DEPS=0 (skip pacman),
#      INSTALL=1 (also untar the result at /).
#
# Panfrost's precompiled kernels need mesa_clc/vtn_bindgen2 (LLVM, clang, libclc, SPIR-V translator) at build
# time, so stage 1 builds those two host tools with LLVM and stage 2 builds the driver with -Dllvm=disabled
# -Dmesa-clc=system.
set -euo pipefail
V=26.2.4
SHA256=bce5f7fbebb934373b86c999a064d52fb5065878dc57f287f95346648ec832e9   # same as Arch's PKGBUILD
PREFIX=${PREFIX:-/opt/quigon-gpu/mesa-panfrost}
here=$(cd "$(dirname "$0")" && pwd)
PATCH=${PATCH:-$here/../port/quigon/patches/mesa-panfrost-ro-vertex-ssbo.patch}
WORK=${WORK:-/root/mesa-panfrost}
OUT=${OUT:-$WORK/mesa-panfrost-$V-aarch64.tar.gz}
JOBS=${JOBS:-$(nproc)}
[[ -f $PATCH ]] || { echo "missing $PATCH" >&2; exit 1; }

if [[ ${DEPS:-1} != 0 ]]; then
  # shellcheck disable=SC2086
  pacman -S --noconfirm --needed ${PACMAN_FLAGS:-} base-devel curl meson ninja python-mako python-yaml \
    python-packaging python-ply python-setuptools bison flex glslang spirv-tools llvm clang libclc \
    spirv-llvm-translator libdrm wayland wayland-protocols libglvnd libx11 libxext libxfixes libxshmfence \
    libxxf86vm libxrandr libxcb zlib zstd expat libelf >/dev/null 2>&1
fi

mkdir -p "$WORK"; cd "$WORK"
[[ -f mesa-$V.tar.xz ]] || curl -sfLO "https://archive.mesa3d.org/mesa-$V.tar.xz"
echo "$SHA256  mesa-$V.tar.xz" | sha256sum -c --quiet
rm -rf "mesa-$V" && tar xf "mesa-$V.tar.xz" && cd "mesa-$V"
patch -p1 --no-backup-if-mismatch < "$PATCH"

log() { echo "== $*"; }
run() { local l=$WORK/$1.log; shift; "$@" > "$l" 2>&1 || { tail -40 "$l"; echo "FAILED, see $l" >&2; exit 1; }; }

log "stage 1: mesa_clc + vtn_bindgen2 (host tools, LLVM)"
run clc-setup meson setup build-clc --buildtype=release -Db_ndebug=true -Dmesa-clc=enabled -Dinstall-mesa-clc=true \
  -Dgallium-drivers= -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
  -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dllvm=enabled -Dshared-llvm=enabled -Dvideo-codecs= \
  -Dtools= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled
run clc-build ninja -C build-clc -j"$JOBS" src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2
mkdir -p hosttools
cp build-clc/src/compiler/clc/mesa_clc build-clc/src/compiler/spirv/vtn_bindgen2 hosttools/
export PATH=$PWD/hosttools:$PATH

log "stage 2: Panfrost (no LLVM)"
run setup meson setup build --prefix="$PREFIX" --buildtype=release -Db_ndebug=true \
  -Dgallium-drivers=panfrost -Dvulkan-drivers= -Dplatforms=wayland,x11 -Dglx=disabled -Degl=enabled \
  -Dgbm=enabled -Dglvnd=enabled -Dllvm=disabled -Dmesa-clc=system -Dgles1=disabled -Dgles2=enabled \
  -Dvideo-codecs= -Dtools= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dzstd=enabled
run build ninja -C build -j"$JOBS"
rm -rf "$WORK/stage"
run install env DESTDIR="$WORK/stage" ninja -C build install
# Headers and pkg-config files aren't needed by the wrapper.
rm -rf "$WORK/stage$PREFIX/include" "$WORK/stage$PREFIX/lib/pkgconfig"
tar -C "$WORK/stage" -czf "$OUT" "${PREFIX#/}"
log "built $OUT"; tar -tzf "$OUT" | sed -n '1,40p'
if [[ ${INSTALL:-0} == 1 ]]; then tar -C / -xzf "$OUT"; log "installed to $PREFIX"; fi
