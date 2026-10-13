#!/usr/bin/python3 -I
# swapbench.py <MB> [runs]: run swapbench in a transient scope, push its memory to zram (memory.reclaim), time the
# swap-in. Prints zram's compression ratio for the pushed data. Source data: the system's shared libraries.
# Build swapbench.c as /tmp/swapbench first (gcc -O2 -o /tmp/swapbench swapbench.c).
import os, subprocess, sys, time, glob
mb, runs = int(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else 3
src = "/tmp/swapbench-src"
if not os.path.exists(src):
    with open(src, "wb") as f:
        n = 0
        for p in sorted(glob.glob("/usr/lib/*.so*")):
            if n > 96 << 20: break
            try: d = open(p, "rb").read()
            except OSError: continue
            f.write(d); n += len(d)
alg = open("/sys/block/zram0/comp_algorithm").read().split("[")[1].split("]")[0]
for r in range(runs):
    p = subprocess.Popen(["systemd-run", "-q", "--scope", "-p", "MemoryAccounting=yes", "/tmp/swapbench", str(mb), src],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    assert p.stdout.readline().strip() == "filled"
    pid = int(subprocess.check_output(["pgrep", "-n", "-x", "swapbench"]).strip())
    cg = "/sys/fs/cgroup" + open(f"/proc/{pid}/cgroup").read().split("::")[1].strip()
    def zr():
        f = open("/sys/block/zram0/mm_stat").read().split(); return int(f[0]), int(f[1])
    a = zr()
    for _ in range(20):
        try:
            with open(f"{cg}/memory.reclaim", "w") as f: f.write(f"{mb * 2}M")
        except OSError: pass
        if int(open(f"{cg}/memory.current").read()) < (mb << 20) * 0.05: break
    b = zr()
    left = int(open(f"{cg}/memory.current").read()) >> 20
    p.stdin.write("go\n"); p.stdin.flush()
    res = p.stdout.readline().strip(); p.wait()
    orig, comp = b[0] - a[0], b[1] - a[1]
    print(f"{alg}: swap-in {res}; pushed {orig >> 20} MB -> {comp >> 20} MB (ratio {orig / max(comp, 1):.2f}), {left} MB left resident", flush=True)
    time.sleep(2)
