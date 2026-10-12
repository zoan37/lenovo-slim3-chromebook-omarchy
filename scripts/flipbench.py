#!/usr/bin/python3 -I
# flipbench.py <n-elements> <seconds> <setting...>: open a throw-away Chrome window with a heavy CSS animation
# (n rotating, shadowed, rounded boxes), then for each Hyprland setting (e.g. "nrs=0" "nrs=1") count the frames the
# display actually received (GCE interrupts: every page flip goes through a GCE packet) over <seconds>.
import os, subprocess, sys, time, urllib.parse

n, secs, settings = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3:]
boxes = "".join(f'<div style="left:{(i*37)%92}vw;top:{(i*53)%86}vh;animation-delay:-{(i%50)/10}s"></div>' for i in range(n))
page = ("<html><body style='margin:0;background:#fff;overflow:hidden'><style>"
        "div{position:absolute;width:90px;height:90px;border-radius:18px;background:linear-gradient(45deg,#e66,#66e);"
        "box-shadow:0 8px 24px rgba(0,0,0,.45);opacity:.85;animation:s 2s linear infinite}"
        "@keyframes s{from{transform:rotate(0) scale(1)}50%{transform:rotate(180deg) scale(1.4)}to{transform:rotate(360deg) scale(1)}}"
        f"</style>{boxes}</body></html>")
url = "data:text/html," + urllib.parse.quote(page)
prof = "/tmp/flipbench-prof"
subprocess.run(["rm", "-rf", prof])
chrome = subprocess.Popen(["/usr/local/bin/quigon-chrome", f"--user-data-dir={prof}", "--no-first-run", "--no-default-browser-check",
                           "--ozone-platform=wayland", "--disable-background-timer-throttling", url],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def cmdq():
    for line in open("/proc/interrupts"):
        if "mtk_cmdq" in line:
            return int(line.split()[1])
    return 0

def hypr(expr):
    subprocess.run(["hyprctl", "eval", expr], stdout=subprocess.DEVNULL)

time.sleep(8)
for s in settings:
    key, val = s.split("=")
    if key == "nrs":
        hypr(f"hl.config({{ render = {{ new_render_scheduling = {'true' if val == '1' else 'false'} }} }})")
    time.sleep(3)
    a, t0 = cmdq(), time.time()
    time.sleep(secs)
    fps = (cmdq() - a) / (time.time() - t0)
    print(f"{n} boxes, {s}: {fps:.1f} frames/s delivered", flush=True)
chrome.terminate()
try:
    chrome.wait(timeout=10)
except Exception:
    chrome.kill()
subprocess.run(["rm", "-rf", prof])
hypr("hl.config({ render = { new_render_scheduling = false } })")
