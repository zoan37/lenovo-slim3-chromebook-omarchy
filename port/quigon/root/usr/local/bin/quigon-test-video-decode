#!/bin/bash
# Regression test for hardware video decode: encodes short 1080p60 H.264 (High, B-pyramid, so frame_num wraps)
# and VP9 clips, decodes them through the VA-API driver in /opt/quigon-gpu/va and in software, and compares every
# frame's md5. Run on the device (any user in the video group) after libva, kernel or driver changes.
set -uo pipefail
export LIBVA_DRIVERS_PATH=${LIBVA_DRIVERS_PATH:-/opt/quigon-gpu/va} LIBVA_DRIVER_NAME=v4l2_request
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
src="testsrc2=size=1920x1080:rate=60,format=yuv420p"
ffmpeg -loglevel error -f lavfi -i "$src" -t 4 -c:v libx264 -profile:v high -preset veryfast -bf 2 -g 120 "$w/h264.mp4" || exit 1
ffmpeg -loglevel error -f lavfi -i "$src" -t 4 -c:v libvpx-vp9 -b:v 6M -deadline realtime -cpu-used 8 -g 120 "$w/vp9.webm" || exit 1
rc=0
for f in "$w/h264.mp4" "$w/vp9.webm"; do
  timeout -s KILL 60 ffmpeg -loglevel error -init_hw_device vaapi=va:/dev/dri/renderD128 -hwaccel vaapi -hwaccel_device va \
    -hwaccel_output_format vaapi -i "$f" -vf hwdownload,format=nv12,format=yuv420p -f framemd5 "$f.hw" 2>"$f.log"
  ffmpeg -loglevel error -i "$f" -pix_fmt yuv420p -f framemd5 "$f.sw"
  hw=$(grep -v '^#' "$f.hw" | awk -F, '{print $NF}'); sw=$(grep -v '^#' "$f.sw" | awk -F, '{print $NF}')
  n=$(wc -l <<<"$sw"); bad=$(diff <(echo "$hw") <(echo "$sw") | grep -c '^>')
  if [[ -n $hw && $bad == 0 ]]; then echo "$(basename "$f"): $n frames bit-exact"
  else echo "$(basename "$f"): $bad of $n frames differ"; grep -v -E "detected|decoding|using CAPTURE|converting MM21" "$f.log" | head -3; rc=1; fi
done
exit $rc
