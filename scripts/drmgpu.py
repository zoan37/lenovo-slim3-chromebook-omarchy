#!/usr/bin/python3 -I
# drmgpu.py <pid> <seconds>: GPU busy time of one process over an interval, from its DRM fdinfo (panfrost profiling
# must be on). Clients are keyed by drm-client-id (several fds can share one); clients that appear during the interval
# count from zero, ones that disappear are lost (rare for a compositor).
import os, sys, time
def snap(pid):
    r = {}
    d = f"/proc/{pid}/fdinfo"
    for fd in os.listdir(d):
        try: txt = open(f"{d}/{fd}").read()
        except OSError: continue
        if "drm-client-id" not in txt: continue
        kv = dict(l.split(":", 1) for l in txt.splitlines() if ":" in l)
        cid = kv["drm-client-id"].strip()
        r[cid] = sum(int(kv[k].split()[0]) for k in kv if k.startswith("drm-engine-"))
    return r
pid, secs = int(sys.argv[1]), float(sys.argv[2])
a = snap(pid); t = time.time(); time.sleep(secs); b = snap(pid); dt = time.time() - t
busy = sum(v - a.get(c, 0) for c, v in b.items() if v >= a.get(c, 0))
print(f"{busy / 1e9 / dt * 100:.1f}")
