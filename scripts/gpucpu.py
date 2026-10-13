#!/usr/bin/python3 -I
# gpucpu.py <n-boxes> <seconds> <mesa-prefix|system>...: CPU cost of the GL driver. For each Mesa build, run a
# throw-away Chrome on a fixed CSS animation (n rotating, shadowed boxes) and measure its GPU process's CPU time per
# frame delivered (frames = GCE interrupts, one per page flip). Run as the desktop user, cwd = home.
import os, subprocess, sys, time, urllib.parse
n, secs, builds = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3:]
boxes = "".join(f'<div style="left:{(i*37)%92}vw;top:{(i*53)%86}vh;animation-delay:-{(i%50)/10}s"></div>' for i in range(n))
page = ("<html><body style='margin:0;background:#fff;overflow:hidden'><style>"
        "div{position:absolute;width:90px;height:90px;border-radius:18px;background:linear-gradient(45deg,#e66,#66e);"
        "box-shadow:0 8px 24px rgba(0,0,0,.45);opacity:.85;animation:s 2s linear infinite}"
        "@keyframes s{from{transform:rotate(0) scale(1)}50%{transform:rotate(180deg) scale(1.4)}to{transform:rotate(360deg) scale(1)}}"
        f"</style>{boxes}</body></html>")
url = "data:text/html," + urllib.parse.quote(page)
HZ = os.sysconf("SC_CLK_TCK")
def cmdq():
    for line in open("/proc/interrupts"):
        if "mtk_cmdq" in line: return int(line.split()[1])
def cpu(pid):
    f = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) / HZ
for b in builds:
    prof = f"/tmp/gpucpu-prof"
    subprocess.run(["rm", "-rf", prof])
    env = dict(os.environ)
    if b != "system":
        env["__EGL_VENDOR_LIBRARY_FILENAMES"] = f"{b}/share/glvnd/egl_vendor.d/50_mesa.json"; env["LD_LIBRARY_PATH"] = f"{b}/lib"
    ch = subprocess.Popen(["/usr/local/bin/quigon-chrome", f"--user-data-dir={prof}", "--no-first-run", "--no-default-browser-check",
                           "--ozone-platform=wayland", url], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(10)
    gpu = None
    for p in os.listdir("/proc"):
        if p.isdigit():
            try:
                c = open(f"/proc/{p}/cmdline", "rb").read()
                if b"--type=gpu-process" in c and prof.encode() in c: gpu = int(p)
            except OSError: pass
    c0, f0, t0 = cpu(gpu), cmdq(), time.time()
    time.sleep(secs)
    c1, f1, dt = cpu(gpu), cmdq(), time.time() - t0
    fr = (f1 - f0)
    print(f"{os.path.basename(b) or b}: {fr/dt:.1f} fps, GPU process {100*(c1-c0)/dt:.0f}% CPU, {1000*(c1-c0)/max(fr,1):.2f} ms CPU/frame", flush=True)
    ch.terminate()
    try: ch.wait(timeout=10)
    except Exception: ch.kill()
    time.sleep(2); subprocess.run(["rm", "-rf", prof])
