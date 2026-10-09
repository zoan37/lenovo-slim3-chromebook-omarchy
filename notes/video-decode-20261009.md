# Hardware video decode in Chrome (2026-10-09)

Result: Chrome uses the MT8189 hardware decoder for **H.264 and VP9 profile 0** through VA-API. The path:
the V4L2 stateless decoder, then a patched `libva-v4l2_request` that detiles MM21 to NV12 on the CPU, then Chrome's
`VaapiVideoDecoder`, then the dma-buf, imported into ANGLE/libmali. 1080p60 VP9 costs Chrome **~0.5 core instead of ~2**.

## Baseline (software decode)

YouTube "2020 LG OLED l The Black 4K HDR 60fps" in Chrome, measured over SSH:

| | renderer (decode) | GPU process | system | dropped |
|---|---|---|---|---|
| VP9 720p60 | 1.17 cores | 0.31 | 1.9 / 8 | 0.2% |
| VP9 1080p60 | 1.78 cores | 0.43 | 2.8 / 8 | 1.1% (21 / 1882) |

YouTube serves VP9 here (`vp09.00.51.08`, itags 302/303), not AV1, which the decoder doesn't have.

## The decoder

- `/dev/video5` `mtk-vcodec-dec` ("MT8189 video decoder", media `/dev/media1`). Stateless `S264`, `VP9F`, `S265`.
  CAPTURE is **`MM21` only**: two planes, 16x32 luma tiles and 16x16 interleaved-chroma tiles, each tile one
  contiguous block. Firmware runs on the SCP (`mediatek/mt8189/scp.img`). There's no separate VCP and no MDP
  (mem2mem converter) on this kernel.
- GStreamer's `v4l2slvp9dec`/`v4l2slh264dec` decode (about 420 fps for 1080p VP9), but the frames GStreamer reads
  back are zeros past the first 4 KiB page. That's GStreamer's `mmap()` of the exported CAPTURE dma-buf on this
  kernel. The VA driver maps CAPTURE through the V4L2 fd (`VIDIOC_QUERYBUF` mem_offset), and that mapping is fine.
- CAPTURE buffers support cache hints (`V4L2_BUF_CAP_SUPPORTS_MMAP_CACHE_HINTS`, caps 0x255).

## VA-API driver: `port/quigon/patches/libva-v4l2-request-mtk-mm21.patch`

On top of sofus13/libva-v4l2_request 1.3 (Omarchy's `libva-v4l2_request-avd` source). Built by
`scripts/build-libva-v4l2-request.sh` into `/opt/quigon-gpu/va/v4l2_request_drv_video.so`, outside pacman's files.
The patch:

- **MM21 format entry + CPU converter** (`convert.c`): MM21 is decoder-only (no VA fourcc), so the driver's existing
  "conversion chain" takes it. Instead of a mem2mem device, `convert_cpu()` detiles each frame into the surface's
  NV12 backing as soon as its CAPTURE buffer is dequeued. Tiles are read sequentially in 64-byte NEON loads and rows
  scattered into the output. Cost per 1080p frame: 6 ms with 16-byte strided reads from the default (uncached)
  mapping, 4 ms with sequential reads, **1.7 ms** with CAPTURE allocated `V4L2_MEMORY_FLAG_NON_COHERENT` (vb2
  invalidates on DQBUF). Clamped to the backing's size: Chrome exports 1920x1080 surfaces, while the decoder works at
  1920x1088.
- **NV12 backing from `/dev/dma_heap/system`**: the driver normally allocates NV12 on the decoder's own CAPTURE
  queue, which here only does MM21. A backing that already exists (Chrome exports surfaces before the first decode)
  is kept, not replaced; replacing it made Chrome show the never-written original (solid green).
- **Multi-planar CAPTURE QBUF/DQBUF**: `length` = the format's plane count (MM21 has 2). It was hardcoded to 1
  (`failed to queue CAPTURE buffer: Invalid argument`).
- **H.264 `pic_num` = PicNum**: the driver passed the raw `frame_num`. With x264's B-pyramid, `frame_num` wraps at 16
  references, about display frame 25, and from then on the MediaTek firmware picks wrong references (blocky smears).
  Now it's FrameNumWrap for short-term refs and LongTermPicNum for long-term, like FFmpeg's v4l2-request.
- **Profiles**: an MM21-only decoder advertises no 10-bit profiles (VP9 Profile 2, HEVC Main10) and **no HEVC**.
  A 10-bit VP9 stream fails at "failed to select a CAPTURE format". HEVC fails at OUTPUT `CREATE_BUFS` (EINVAL), and
  in testing the SCP firmware hit its watchdog and was restarted right then. Not advertising a codec makes sites pick
  one that plays, and Chrome decodes 10-bit VP9 in software.

Verification (`ffmpeg -hwaccel vaapi … -vf hwdownload … -f framemd5` against software decode): VP9 1080p60 and H.264
High 1080p60 (B-pyramid) are **bit-exact for all 600 frames**.

## Chrome side

- Chrome's VA-API decoder exports surfaces (`vaExportSurfaceHandle`, 2 fds, stride 1920, chroma offset 1920*1080)
  and imports them with `gbm_bo_import`. Against ChromeOS's minigbm, every such import failed: **desktop Chrome uses
  Mesa's gbm.h, where `GBM_BO_IMPORT_FD_MODIFIER` = 0x5504; in minigbm's gbm.h it's 0x5505**, and 0x5504 is the
  removed `GBM_BO_IMPORT_FD_PLANAR`, so `gbm_bo_import` returns NULL. Then "Cannot create bo with format=(Y_UV, 420,
  8unorm)", "CreateSharedImage: could not create backing", and the GPU process restarts.
  [`bringup/gbm-linear-shim.c`](../bringup/gbm-linear-shim.c), built as Chrome's `libgbm.so.1` by
  `scripts/build-chrome-lib.sh`, maps the constant. It also adds LINEAR to implicit-only (INVALID) NV12 modifier
  lists, because minigbm's mediatek backend requires LINEAR in the list ("no usable modifier found"). That's
  limited to YUV formats: adding it for RGBA made Chrome probe 1x1 AB24 buffers in a tight loop. minigbm's soname is
  libgbm.so.1 as well, so the shim links a copy renamed with patchelf (`libquigon-minigbm.so`).
- Flags (in `quigon-chrome`, merged with `~/.config/chrome-flags.conf`'s feature lists because Chrome keeps only the
  last `--enable-features`): `--enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,AcceleratedVideoDecodeLinuxGL,
  AcceleratedVideoDecodeLinuxZeroCopyGL --disable-features=UseChromeOSDirectVideoDecoder`, env
  `LIBVA_DRIVERS_PATH=/opt/quigon-gpu/va LIBVA_DRIVER_NAME=v4l2_request` (the render node is `mediatek-drm`, so libva
  would look for `mediatek_drv_video.so`). `--ignore-gpu-blocklist` isn't needed. The GPU sandbox doesn't get in the
  way (`/dev/video5`, `/dev/media1` and `/dev/dma_heap/system` open fine).
- Measured in a separate test profile (`--user-data-dir=/tmp/vachrome`), local 1080p60 VP9 clip, 30 s:

  | | GPU process | renderer | browser | Chrome total | dropped |
  |---|---|---|---|---|---|
  | hardware decode | 0.34 | 0.07 | 0.07 | **0.49 core** | 2 / 1859 |
  | software decode | 0.22 | 1.66 | 0.09 | **1.97 cores** | 3 / 1853 |

- YouTube in the test profile: `VaapiVideoDecoder` takes the VP9 stream (360p at start, then 720p in that window),
  and the picture is correct.

## Hazards found on the way

- **HEVC can crash the decoder firmware.** After the SCP watchdog restart, the vcodec driver keeps a stale instance
  (`vpu_dec_ipi_handler: ap_inst_addr is NULL, did the SCP hang or crash?`, `VP9 decode timeout`), and every decode
  times out until reboot.
- **Don't unbind/rebind `mtk-vcodec-dec` while anything holds `/dev/video5`.** It wedged parts of the system (SSH and
  the bridge hung on processes stuck in the kernel). A reboot is the way out.
- `pkill -f`/`pgrep -f` on a pattern your own shell's command line contains kills the shell (happened twice; the
  test scripts now match on `/proc/PID/exe`).
- gdb can't set breakpoints here: the ChromeOS kernel denies writes to `/proc/PID/mem` ("Denied write call of
  /proc/…/mem (gdb)"), and Chrome's GPU watchdog kills a stopped GPU process anyway.
