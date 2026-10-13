#!/bin/bash
# scanoutbench.sh <secs> <setting...>: fullscreen test video in a throw-away Chrome profile; for each Hyprland
# render:direct_scanout value, measure battery power, Hyprland's GPU time (DRM fdinfo), frames delivered (GCE IRQs).
secs=$1; shift
U=$(id -un 1001); E=(XDG_RUNTIME_DIR=/run/user/1001 WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1001/hypr|head -1))
hc() { sudo -u $U env "${E[@]}" hyprctl "$@"; }
[ -f /tmp/scanout-test.mp4 ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 60 -c:v libx264 -pix_fmt yuv420p -g 60 /tmp/scanout-test.mp4
cat > /tmp/scanout-test.html <<'H'
<html><body style="margin:0;background:#000;overflow:hidden"><video src="scanout-test.mp4" autoplay loop muted style="width:100vw;height:100vh"></video></body></html>
H
chmod 644 /tmp/scanout-test.*
P=/tmp/scanout-prof; rm -rf $P
cd /home/$U
PROF=/sys/bus/platform/drivers/panfrost/13000000.gpu/profiling; echo 1 > $PROF
sudo -u $U env "${E[@]}" /usr/local/bin/quigon-chrome --user-data-dir=$P --no-first-run --no-default-browser-check --ozone-platform=wayland --start-fullscreen \
  --allow-file-access-from-files file:///tmp/scanout-test.html >/dev/null 2>&1 &
sleep 10
hc clients | grep -E 'class:|fullscreen:' | head -4
hp=$(pgrep -x -u $U Hyprland | head -1)
# one value per DRM client (several fds can share a client)
gpu() { awk '/^drm-client-id:/ {id=$2} /^drm-engine-(fragment|vertex-tiler):/ {t[id FILENAME]=0; v[id]+=0; e[id, $1]=$2} END {for (k in e) s+=e[k]; print s+0}' /proc/$hp/fdinfo/* 2>/dev/null; }
irq() { awk '/mtk_cmdq/ {print $2; exit}' /proc/interrupts; }
B=/sys/class/power_supply/sbs-5-000b
for s in "$@"; do
  hc eval "hl.config({ $s })" >/dev/null
  sleep 4
  python3 -I /tmp/drmgpu.py $hp $secs > /tmp/drmgpu.out & gp=$!
  i0=$(irq); t0=$(date +%s%N); pw=0; n=0
  for k in $(seq $secs); do
    sleep 1; c=$(cat $B/current_now); v=$(cat $B/voltage_now); pw=$(( pw + (c<0 ? -c : c) / 1000 * (v / 1000) / 1000 )); n=$((n+1))
  done
  wait $gp; i1=$(irq); t1=$(date +%s%N); dt=$(( (t1-t0)/1000000 ))
  ds=$(hc monitors | awk -F': ' '/directScanoutTo/ {print $2}'); bb=$(hc monitors | awk -F': ' '/directScanoutBlockedBy/ {print $2}')
  echo "$s: $((pw / n)) mW, Hyprland GPU $(cat /tmp/drmgpu.out)%, $(( (i1-i0) * 1000 / dt )) frames/s, scanout=$ds blocked=[$bb]"
done
pkill -u $U -f -- "--user-data-dir=$P" ; sleep 3; rm -rf $P; echo 0 > $PROF
