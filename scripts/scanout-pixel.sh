#!/bin/bash
# scanout-pixel.sh <seconds> <x> <y> (on the Chromebook, root): watch a 4x4 patch at x,y of what the display engine
# from the scanout (kmsgrab); log Shift presses as flicker marks; report every frame whose patch isn't its usual value.
S=${1:-60}; x=$2; y=$3; echo "watching pixel $x,$y"
rm -f /tmp/pix.raw /tmp/marks.txt
python3 -I - "$S" > /tmp/marks.txt <<'PY' &
import evdev, select, sys, time
devs = [evdev.InputDevice(p) for p in evdev.list_devices()]
devs = [d for d in devs if evdev.ecodes.KEY_LEFTSHIFT in d.capabilities().get(evdev.ecodes.EV_KEY, [])]
end = time.time() + float(sys.argv[1]) + 2
while time.time() < end:
    r, _, _ = select.select(devs, [], [], 0.5)
    for d in r:
        for e in d.read():
            if e.type == evdev.ecodes.EV_KEY and e.value == 1 and e.code in (evdev.ecodes.KEY_LEFTSHIFT, evdev.ecodes.KEY_RIGHTSHIFT):
                print(f"{e.timestamp():.3f}", flush=True)
PY
date +%s.%N > /tmp/rec-start.txt
ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card1 -f kmsgrab -framerate 60 -i - -t "$S" \
  -vf "hwdownload,format=bgr0,crop=4:4:$x:$y" -f rawvideo -pix_fmt rgb24 /tmp/pix.raw
wait
python3 -I - <<'PY'
from collections import Counter
N = 4 * 4 * 3
d = open("/tmp/pix.raw", "rb").read(); n = len(d) // N; fps = 59.0
t0 = float(open("/tmp/rec-start.txt").read())
px = [tuple(d[i*N:i*N+3]) for i in range(n)]                     # top-left pixel RGB
avg = [sum(d[i*N:(i+1)*N]) / N for i in range(n)]                # patch average
marks = [float(l) - t0 for l in open("/tmp/marks.txt") if l.strip()]
common = Counter(px).most_common(1)[0]
print(f"{n} frames; Shift marks at {[f'{m:.1f}s' for m in marks]}")
print(f"usual pixel {common[0]} in {100*common[1]/n:.1f}% of frames; patch average min {min(avg):.1f} max {max(avg):.1f}")
odd = [i for i in range(n) if px[i] != common[0]]
runs = []
for i in odd:
    if runs and i == runs[-1][1] + 1: runs[-1][1] = i
    else: runs.append([i, i])
print(f"frames that differ: {len(odd)} in {len(runs)} runs")
for a, b in runs[:40]:
    print(f"  {a/fps:6.2f}s-{b/fps:6.2f}s ({b-a+1} frames): {px[a]} .. min avg {min(avg[a:b+1]):.1f}")
PY
rm -f /tmp/pix.raw
