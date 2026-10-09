#!/bin/bash
# Build ARM's Vulkan WSI layer (adds VK_KHR_wayland_surface to ChromeOS's headless-only libmali Vulkan driver) on the
# device, with the quigon patch (explicit sync optional: Hyprland has no zwp_linux_explicit_synchronization_v1; DRM
# properties filled in so Mesa Zink can match the device) and the
# "system" DMA-BUF heap (this kernel has no "linux,cma" heap). Installs the Mali ICD + layer system-wide. Run as root.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=/root/vulkan-wsi-layer
[[ -d $src ]] || git clone https://gitlab.freedesktop.org/mesa/vulkan-wsi-layer.git $src
cd $src && git checkout -q f5148d4f8c541f8aeddc88170b9e2dbbea2e8b43 && git checkout -q -- .
git apply "$here/../port/quigon/patches/vulkan-wsi-layer-quigon.patch"
sed -i 's/ -Werror//g' CMakeLists.txt   # GCC 16 maybe-uninitialized false positive in wsialloc_helpers.c
pacman -S --noconfirm --needed cmake vulkan-headers vulkan-icd-loader wayland wayland-protocols libdrm >/dev/null
cmake . -Bbuild -DCMAKE_BUILD_TYPE=Release -DBUILD_WSI_HEADLESS=1 -DBUILD_WSI_WAYLAND=1 \
  -DSELECT_EXTERNAL_ALLOCATOR=dma_buf_heaps -DWSIALLOC_MEMORY_HEAP_NAME=system -DKERNEL_HEADER_DIR=/usr/include
make -C build -j$(nproc)
D=/opt/quigon-gpu/vulkan/layer; install -d $D
install -m755 build/libVkLayer_window_system_integration.so $D/
sed "s#\"./libVkLayer_window_system_integration.so\"#\"$D/libVkLayer_window_system_integration.so\"#" \
  build/VkLayer_window_system_integration.json > $D/VkLayer_window_system_integration.json
printf '{\n  "ICD": { "api_version": "1.3.211", "library_path": "/opt/quigon-gpu/mali/lib/libmali.so.0" },\n  "file_format_version": "1.0.0"\n}\n' > /opt/quigon-gpu/vulkan/mali_icd.json
install -d /etc/vulkan/icd.d /etc/vulkan/implicit_layer.d
ln -sf /opt/quigon-gpu/vulkan/mali_icd.json /etc/vulkan/icd.d/quigon_mali_icd.json
ln -sf $D/VkLayer_window_system_integration.json /etc/vulkan/implicit_layer.d/quigon_wsi_layer.json
echo 'SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660"' > /etc/udev/rules.d/70-quigon-dma-heap.rules
udevadm control --reload && udevadm trigger --subsystem-match=dma_heap || true
