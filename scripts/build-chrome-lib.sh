#!/bin/bash
# /opt/quigon-gpu/chrome-lib: what quigon-chrome puts first on Chrome's LD_LIBRARY_PATH.
#   libEGL.so.1    = egl-mali-shim built as a proxy library with DT_NEEDED libmali.so.0 (ANGLE dlopen()s libEGL.so.1
#                    and dlsym()s on that handle, so an LD_PRELOAD shim never sees its calls)
#   libGLESv2.so.2 = libmali
#   libgbm.so.1    = bringup/gbm-linear-shim.c in front of ChromeOS minigbm (mediatek backend, RELR-patched like libmali
#                    with scripts/patch-cros-relr.py), linked as libquigon-minigbm.so (minigbm's own soname is
#                    libgbm.so.1 too). The shim maps Chrome's (Mesa) GBM_BO_IMPORT_FD_MODIFIER to minigbm's value and
#                    adds LINEAR to implicit-only NV12 modifier lists; without it every dma-buf import and every video
#                    frame allocation fails (hardware video decode needs both).
# Run as root on the device after libmali is staged in /opt/quigon-gpu/mali/lib and libminigbm.so.1.0.0.relr is there.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
D=/opt/quigon-gpu/chrome-lib; M=/opt/quigon-gpu/mali/lib
install -d $D
gcc -O2 -Wall -shared -fPIC -o $D/libEGL.so.1 "$here/../bringup/egl-mali-shim.c" -Wl,-soname,libEGL.so.1 \
  -Wl,--no-as-needed -L$M -Wl,-rpath,$M -Wl,-rpath-link,$M -l:libmali.so.0 -ldl
ln -sf $M/libmali.so.0 $D/libGLESv2.so.2
ln -sf $M/libmali.so.0 $D/libGLESv1_CM.so.1
command -v patchelf >/dev/null || pacman -S --noconfirm --needed patchelf
cp $M/libminigbm.so.1.0.0.relr $M/libquigon-minigbm.so
patchelf --set-soname libquigon-minigbm.so $M/libquigon-minigbm.so
rm -f $D/libgbm.so.1
gcc -O2 -Wall -shared -fPIC -o $D/libgbm.so.1 "$here/../bringup/gbm-linear-shim.c" -Wl,-soname,libgbm.so.1 \
  -Wl,--no-as-needed -L$M -Wl,-rpath,$M -l:libquigon-minigbm.so -ldl
