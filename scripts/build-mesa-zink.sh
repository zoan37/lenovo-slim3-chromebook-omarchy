#!/bin/bash
# Private Mesa (zink only) for Ghostty: lets vertex shaders keep read-only SSBOs on drivers without
# vertexPipelineStoresAndAtomics when QUIGON_ZINK_RO_VERTEX_SSBO=1.
set -euo pipefail
V=26.2.4
pacman -S --noconfirm --needed meson ninja python-mako python-yaml python-packaging python-ply bison flex glslang spirv-tools \
  libdrm wayland wayland-protocols libglvnd vulkan-headers vulkan-icd-loader zlib zstd expat libelf >/dev/null
cd /root
[[ -f mesa-$V.tar.xz ]] || curl -sfLO https://archive.mesa3d.org/mesa-$V.tar.xz
rm -rf mesa-$V && tar xf mesa-$V.tar.xz && cd mesa-$V
python3 - <<'PY'
p = "src/gallium/drivers/zink/zink_screen.c"; s = open(p).read()
old = """         if (!screen->info.feats.features.vertexPipelineStoresAndAtomics)
            caps->max_shader_buffers = 0;"""
new = """         /* quigon: Vulkan allows read-only storage buffers in pre-rasterization stages without
          * vertexPipelineStoresAndAtomics; opt in for apps that only read them (Ghostty). */
         if (!screen->info.feats.features.vertexPipelineStoresAndAtomics &&
             !debug_get_bool_option("QUIGON_ZINK_RO_VERTEX_SSBO", false))
            caps->max_shader_buffers = 0;"""
assert s.count(old) == 1; open(p, "w").write(s.replace(old, new)); print("patched zink_screen.c")
PY
meson setup build --prefix=/opt/quigon-gpu/mesa-zink --buildtype=release -Db_ndebug=true \
  -Dgallium-drivers=zink -Dvulkan-drivers= -Dplatforms=wayland -Dglx=disabled -Degl=enabled -Dgbm=enabled \
  -Dglvnd=enabled -Dllvm=disabled -Dgles1=disabled -Dgles2=enabled -Dvideo-codecs= -Dtools= -Dvalgrind=disabled \
  -Dlibunwind=disabled -Dlmsensors=disabled -Dzstd=enabled > /root/mesa-zink-setup.log 2>&1 || { tail -30 /root/mesa-zink-setup.log; exit 1; }
ninja -C build -j8 > /root/mesa-zink-build.log 2>&1 || { tail -30 /root/mesa-zink-build.log; exit 1; }
ninja -C build install > /root/mesa-zink-install.log 2>&1
echo "BUILD OK"; ls /opt/quigon-gpu/mesa-zink/lib /opt/quigon-gpu/mesa-zink/share/glvnd/egl_vendor.d 2>&1
