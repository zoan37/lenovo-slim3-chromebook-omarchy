# scanout-vline-window.py <from s> <to s> <settled s>: after scanout-vline.sh, list thin vertical lines that appear between
# <from> and <to> and are gone by <settled> (/tmp/strip.gray, 1920x40, ~59 fps).
import sys
W, H = 1920, 40; N = W * H
d = open("/tmp/strip.gray", "rb").read(); n = len(d) // N; fps = 59.0
t_a, t_b, t_after = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
def cols(i):
    f = d[i*N:(i+1)*N]; return [sum(f[y*W + x] for y in range(H)) / H for x in range(W)]
def lines(c, thr=30):
    return {x for x in range(2, W-2) if abs(c[x] - (c[x-2] + c[x+2]) / 2) > thr}
a, b = int(t_a*fps), min(n, int(t_b*fps))
after = lines(cols(min(n-1, int(t_after*fps))))
for i in range(a, b):
    c = cols(i); L = sorted(x for x in lines(c) - after if 300 < x < 1620)
    m = sum(c) / W
    if L:
        more = " ..." if len(L) > 12 else ""
        print(f"t={i/fps:5.2f}s mean={m:5.1f} new line-columns ({len(L)}): {L[:12]}{more}")
    elif i % 6 == 0:
        print(f"t={i/fps:5.2f}s mean={m:5.1f} -")
