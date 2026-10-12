#!/usr/bin/python3 -I
# launchbench.py <runs> <class-regex> <command...>: time from running the command to Hyprland's openwindow event for a
# window whose class matches, then close that window. Run as the desktop user inside the Hyprland environment.
import glob, os, re, socket, subprocess, sys, time

runs, cls, cmd = int(sys.argv[1]), re.compile(sys.argv[2]), sys.argv[3:]
d = os.path.dirname(sorted(glob.glob(f"/run/user/{os.getuid()}/hypr/*/.socket2.sock"), key=os.path.getmtime)[-1])
times = []
for r in range(runs):
    s = socket.socket(socket.AF_UNIX); s.connect(os.path.join(d, ".socket2.sock")); s.settimeout(20)
    t0 = time.monotonic()
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    buf, addr = b"", None
    try:
        while addr is None:
            buf += s.recv(65536)
            *lines, buf = buf.split(b"\n")
            for l in lines:
                l = l.decode(errors="replace")
                if l.startswith("openwindow>>"):
                    a, ws, c, title = (l[12:].split(",", 3) + ["", "", ""])[:4]
                    if cls.search(c):
                        addr = a; break
    except socket.timeout:
        print(f"run {r+1}: no window within 20 s"); continue
    dt = time.monotonic() - t0
    times.append(dt)
    print(f"run {r+1}: {dt*1000:.0f} ms", flush=True)
    time.sleep(1.5)
    subprocess.run(["hyprctl", "dispatch", f'hl.dsp.window.close({{ window = "address:0x{addr}" }})'], stdout=subprocess.DEVNULL)
    time.sleep(2.5)
if times:
    print(f"median {sorted(times)[len(times)//2]*1000:.0f} ms")
