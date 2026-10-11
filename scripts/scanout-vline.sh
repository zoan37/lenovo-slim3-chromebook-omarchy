#!/bin/bash
# scanout-vline.sh <seconds> (on the Chromebook, root): record a 1920x40 strip (rows 580-619) of the scanout at ~59 fps (gray) plus Hyprland window
# events; then find frames with a thin vertical line (a column much darker/brighter than both neighbours over the strip).
S=${1:-25}
rm -f /tmp/strip.gray /tmp/hev.txt
python3 -I - "$S" > /tmp/hev.txt <<'PY' &
import glob, os, socket, sys, time
p = sorted(glob.glob("/run/user/*/hypr/*/.socket2.sock"), key=os.path.getmtime)[-1]
s = socket.socket(socket.AF_UNIX); s.connect(p); s.settimeout(0.5); buf = b""; end = time.time() + float(sys.argv[1])
while time.time() < end:
    try: buf += s.recv(4096)
    except socket.timeout: continue
    *lines, buf = buf.split(b"\n")
    for l in lines:
        l = l.decode(errors="replace")
        if l.split(">>")[0] in ("openwindow", "closewindow"): print(f"{time.time():.3f} {l[:100]}", flush=True)
PY
date +%s.%N > /tmp/rec-start.txt
ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card1 -f kmsgrab -framerate 60 -i - -t "$S" \
  -vf "hwdownload,format=bgr0,crop=1920:40:0:580,format=gray" -f rawvideo /tmp/strip.gray
wait
python3 -I - <<'PY'
W, H = 1920, 40; N = W * H
d = open("/tmp/strip.gray", "rb").read(); n = len(d) // N; fps = 59.0
t0 = float(open("/tmp/rec-start.txt").read())
for l in open("/tmp/hev.txt"):
    t, e = l.split(" ", 1); print(f"event {float(t)-t0:6.2f}s {e.strip()}")
hits = []
for i in range(n):
    f = d[i*N:(i+1)*N]
    col = [sum(f[y*W + x] for y in range(H)) / H for x in range(W)]
    best = max(((abs(col[x] - (col[x-2] + col[x+2]) / 2), x) for x in range(400, 1520)), default=(0, 0))
    if best[0] > 40: hits.append((i, best[1], best[0], col[best[1]], (col[best[1]-2]+col[best[1]+2])/2))
print(f"{n} frames; frames with a thin vertical line in the middle 1120 columns: {len(hits)}")
for i, x, s, c, nb in hits[:40]:
    print(f"  frame {i:4d} t={i/fps:6.2f}s  x={x}  column {c:5.1f} vs neighbours {nb:5.1f}")
PY
