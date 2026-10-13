#!/bin/bash
# schedbench.sh <sched...>: for each scheduler ("eevdf" = the kernel's own, or an scx_* binary with its arguments,
# e.g. "scx_lavd" "scx_bpfland"), measure (1) burst latency with no load, (2) burst latency and (3) a Chrome CSS
# animation's frame rate while 8 CPU hogs run. Bursts: sha256 of 4 MiB after 0.3 s idle, 30 times, in a scope with
# cpu.uclamp.min 40 (what uclamp-boost gives the focused app). Run as root on the Chromebook.
U=$(id -un 1001)
probe() {   # prints median / p90 / max ms
  systemd-run -q --scope -p CPUWeight=100 bash -c '
    cg=/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup); echo max > /sys/fs/cgroup/system.slice/cpu.uclamp.min; echo 40 > $cg/cpu.uclamp.min
    for i in $(seq 30); do sleep 0.3; a=$(date +%s%N); head -c 4194304 /dev/zero | sha256sum >/dev/null; b=$(date +%s%N); echo $(( (b-a)/100000 )); done' |
    sort -n | awk '{v[NR]=$1/10} END {printf "median %.1f / p90 %.1f / max %.1f ms", v[int(NR/2)+1], v[int(NR*0.9)], v[NR]}'
}
load_on() { systemd-run -q --unit schedload -p CPUWeight=100 bash -c 'for i in 1 2 3 4 5 6 7 8; do sha256sum /dev/zero & done; wait'; sleep 2; }
load_off() { systemctl stop schedload; sleep 2; }
for s in "$@"; do
  pid=""
  if [ "$s" != eevdf ]; then
    $s >/tmp/scx-$$.log 2>&1 & pid=$!; sleep 4
    [ "$(cat /sys/kernel/sched_ext/state)" = enabled ] || { echo "$s: did not attach ($(tail -2 /tmp/scx-$$.log))"; kill $pid 2>/dev/null; continue; }
  fi
  echo "== $s ($(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo eevdf))"
  echo "  idle:  burst $(probe)"
  load_on
  echo "  load:  burst $(probe)"
  echo "  load:  chrome $(cd /home/$U && sudo -u $U env XDG_RUNTIME_DIR=/run/user/1001 WAYLAND_DISPLAY=wayland-1 python3 -I /tmp/gpucpu.py 150 15 system 2>&1 | sed 's/^system: //')"
  load_off
  [ -n "$pid" ] && { kill -INT $pid; wait $pid 2>/dev/null; sleep 2; }
done
echo 0 > /sys/fs/cgroup/system.slice/cpu.uclamp.min
