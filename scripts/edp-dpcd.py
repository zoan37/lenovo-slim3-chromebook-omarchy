#!/usr/bin/python3 -I
# edp-dpcd.py: read the eDP panel's backlight capabilities and mode from DPCD through /dev/drm_dp_aux* (read-only).
import glob, os
def rd(dev, off, n):
    fd = os.open(dev, os.O_RDONLY)
    try:
        os.lseek(fd, off, 0); return os.read(fd, n)
    finally:
        os.close(fd)
for dev in sorted(glob.glob("/dev/drm_dp_aux*")):
    name = open(f"/sys/class/drm_dp_aux_dev/{os.path.basename(dev)}/name").read().strip()
    try:
        b = rd(dev, 0x700, 4); m = rd(dev, 0x720, 2)
    except OSError as e:
        print(dev, name, "read failed:", e); continue
    rev, cap1, adj, cap2 = b
    print(f"{dev} ({name}): eDP DPCD rev 0x{rev:02x}")
    print(f"  0x701 general cap 1 = 0x{cap1:02x}: TCON backlight adj {cap1>>0&1}, AUX backlight enable {cap1>>2&1}, FRC {cap1>>5&1}")
    print(f"  0x702 backlight adj cap = 0x{adj:02x}: PWM pin {adj&1}, AUX brightness {adj>>1&1}, DYNAMIC BACKLIGHT CAP {adj>>6&1}")
    print(f"  0x703 general cap 2 = 0x{cap2:02x}")
    print(f"  0x720 display control = 0x{m[0]:02x}")
    print(f"  0x721 backlight mode = 0x{m[1]:02x}: control mode {m[1]&3} (0 PWM pin, 2 DPCD), DYNAMIC BACKLIGHT ENABLED {m[1]>>4&1}, regional {m[1]>>5&1}")
