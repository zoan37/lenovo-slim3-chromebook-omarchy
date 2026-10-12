#!/usr/bin/python3 -I
# palmbench.py <filter-copy> <frames> [uclamp_min]: (filter-copy = quigon-palm-filter with its device name changed to
# "Elan Touchpad bench") latency of the palm filter's evdev -> uinput hop. Feeds synthetic
# one-finger frames (125 Hz) into a uinput "Elan Touchpad bench" device, runs a copy of the filter on it as a transient
# system service (as quigon-palm-filter.service runs), and times each frame from injection to the filter's output event
# (kernel timestamps). A udev rule in /run makes libinput ignore both bench devices, so the cursor doesn't move.
import os, subprocess, sys, time, select
import evdev
from evdev import ecodes as e

copy, frames = sys.argv[1], int(sys.argv[2])
umin = sys.argv[3] if len(sys.argv) > 3 else None
RULE = "/run/udev/rules.d/99-palmbench.rules"
os.makedirs(os.path.dirname(RULE), exist_ok=True)
open(RULE, "w").write('ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="Elan Touchpad bench*", ENV{LIBINPUT_IGNORE_DEVICE}="1"\n')
subprocess.run(["udevadm", "control", "--reload"])
real = next(evdev.InputDevice(p) for p in evdev.list_devices() if evdev.InputDevice(p).name == "Elan Touchpad")
codes = (e.ABS_X, e.ABS_Y, e.ABS_PRESSURE, e.ABS_MT_SLOT, e.ABS_MT_POSITION_X, e.ABS_MT_POSITION_Y,
         e.ABS_MT_TRACKING_ID, e.ABS_MT_PRESSURE, e.ABS_MT_TOUCH_MAJOR)
caps = {e.EV_KEY: [e.BTN_LEFT, e.BTN_TOUCH, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP, e.BTN_TOOL_TRIPLETAP,
                   e.BTN_TOOL_QUADTAP, e.BTN_TOOL_QUINTTAP],
        e.EV_ABS: [(c, real.absinfo(c)) for c in codes]}
src = evdev.UInput(caps, name="Elan Touchpad bench", input_props=[e.INPUT_PROP_POINTER, e.INPUT_PROP_BUTTONPAD])
time.sleep(1)
unit = "palmbench"
subprocess.run(["systemctl", "stop", unit], stderr=subprocess.DEVNULL)
subprocess.run(["systemctl", "reset-failed", unit], stderr=subprocess.DEVNULL)
subprocess.run(["systemd-run", "-q", "--unit", unit, "-p", "CPUWeight=100", "/usr/bin/python3", copy], check=True)
out = None
for _ in range(50):
    time.sleep(0.1)
    for p in evdev.list_devices():
        d = evdev.InputDevice(p)
        if d.name == "Elan Touchpad bench (palm filter)":
            out = d
    if out: break
if not out:
    sys.exit("filter output device not found")
if umin:
    cg = "/sys/fs/cgroup/system.slice/palmbench.service"
    open(f"{cg}/cpu.uclamp.min", "w").write(umin)
time.sleep(0.5)
lat = []
x0, y0 = 1200, 1100
def frame(i, down=True, first=False):
    if first:
        src.write(e.EV_ABS, e.ABS_MT_SLOT, 0); src.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, 100)
        src.write(e.EV_KEY, e.BTN_TOUCH, 1); src.write(e.EV_KEY, e.BTN_TOOL_FINGER, 1)
    if down:
        x, y = x0 + (i % 800), y0 + (i % 300)
        src.write(e.EV_ABS, e.ABS_MT_POSITION_X, x); src.write(e.EV_ABS, e.ABS_MT_POSITION_Y, y)
        src.write(e.EV_ABS, e.ABS_MT_PRESSURE, 25 + i % 3); src.write(e.EV_ABS, e.ABS_MT_TOUCH_MAJOR, 90 + i % 4)
        src.write(e.EV_ABS, e.ABS_X, x); src.write(e.EV_ABS, e.ABS_Y, y); src.write(e.EV_ABS, e.ABS_PRESSURE, 25)
    else:
        src.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1); src.write(e.EV_KEY, e.BTN_TOUCH, 0)
        src.write(e.EV_KEY, e.BTN_TOOL_FINGER, 0)
    t = time.time(); src.syn(); return t
# strokes of 100 frames at 125 Hz separated by 0.6 s idle (each stroke starts from an idle CPU, like a real swipe)
i, sent_t = 0, []
while i < frames:
    sent_t.append(frame(i, first=True)); i += 1
    for _ in range(99):
        time.sleep(0.008); sent_t.append(frame(i)); i += 1
        while select.select([out], [], [], 0)[0]:
            for ev in out.read():
                if ev.type == e.EV_SYN: lat.append(ev.timestamp())
    time.sleep(0.008); frame(i, down=False)
    time.sleep(0.6)
    while select.select([out], [], [], 0.05)[0]:
        for ev in out.read():
            if ev.type == e.EV_SYN: lat.append(ev.timestamp())
# outputs: one per moving frame plus one per lift; match in order, skipping lifts
outs = lat
d = []
j = 0
for k in range(0, len(sent_t), 100):
    stroke = sent_t[k:k + 100]
    o = outs[j:j + len(stroke)]
    d += [(b - a) * 1000 for a, b in zip(stroke, o)]
    j += len(stroke) + 1
subprocess.run(["systemctl", "stop", unit])
src.close()
os.remove(RULE); subprocess.run(["udevadm", "control", "--reload"])
d.sort()
q = lambda p: d[min(len(d) - 1, int(p * len(d)))]
print(f"uclamp.min={umin or 0}: {len(d)} frames, median {q(0.5):.2f} ms, p90 {q(0.9):.2f}, p99 {q(0.99):.2f}, max {d[-1]:.2f}")
