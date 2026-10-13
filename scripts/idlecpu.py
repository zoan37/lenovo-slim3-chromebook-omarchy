#!/usr/bin/python3 -I
# idlecpu.py <seconds>: CPU time and wakeups (context switches) per process over an interval, top 15.
import os, sys, time
def snap():
    r = {}
    for p in os.listdir("/proc"):
        if not p.isdigit(): continue
        try:
            st = open(f"/proc/{p}/stat").read()
            name = st[st.index("(")+1:st.rindex(")")]
            f = st[st.rindex(")")+2:].split()
            cpu = int(f[11]) + int(f[12])
            sw = 0
            for t in os.listdir(f"/proc/{p}/task"):
                for l in open(f"/proc/{p}/task/{t}/status"):
                    if l.startswith(("voluntary_ctxt", "nonvoluntary_ctxt")): sw += int(l.split()[1])
            r[p] = (name, cpu, sw)
        except (OSError, ValueError): pass
    return r
dt = float(sys.argv[1]); a = snap(); time.sleep(dt); b = snap()
hz = os.sysconf("SC_CLK_TCK"); rows = []
for p, (n, c, s) in b.items():
    if p in a: rows.append(((c - a[p][1]) / hz / dt * 100, (s - a[p][2]) / dt, n, p))
tot = sum(r[0] for r in rows), sum(r[1] for r in rows)
print(f"total {tot[0]:.1f}% CPU, {tot[1]:.0f} wakeups/s")
for cpu, w, n, p in sorted(rows, key=lambda r: -(r[0] * 100 + r[1]))[:15]:
    print(f"{cpu:5.1f}%  {w:6.0f}/s  {n} ({p})")
