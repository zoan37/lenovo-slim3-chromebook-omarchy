#!/bin/bash
# /opt/quigon-gpu/chrome-lib: what quigon-chrome puts first on Chrome's LD_LIBRARY_PATH.
#   libEGL.so.1    = egl-mali-shim built as a proxy library with DT_NEEDED libmali.so.0 (ANGLE dlopen()s libEGL.so.1
#                    and dlsym()s on that handle, so an LD_PRELOAD shim never sees its calls)
#   libGLESv2.so.2 = libmali
#   libgbm.so.1    = ChromeOS minigbm (mediatek backend), RELR-patched like libmali (scripts/patch-cros-relr.py)
# Run as root on the device after libmali is staged in /opt/quigon-gpu/mali/lib and libminigbm.so.1.0.0.relr is there.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
D=/opt/quigon-gpu/chrome-lib; M=/opt/quigon-gpu/mali/lib
install -d $D
gcc -O2 -Wall -shared -fPIC -o $D/libEGL.so.1 "$here/../bringup/egl-mali-shim.c" -Wl,-soname,libEGL.so.1 \
  -Wl,--no-as-needed -L$M -Wl,-rpath,$M -Wl,-rpath-link,$M -l:libmali.so.0 -ldl
ln -sf $M/libmali.so.0 $D/libGLESv2.so.2
ln -sf $M/libmali.so.0 $D/libGLESv1_CM.so.1
ln -sf $M/libminigbm.so.1.0.0.relr $D/libgbm.so.1
