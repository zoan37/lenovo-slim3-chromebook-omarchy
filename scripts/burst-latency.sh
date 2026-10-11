#!/bin/bash
# burst-latency.sh <uclamp-min%>: 15 bursts of fixed CPU work (sha256 of 4 MiB), 0.6 s idle before each, in the
# current cgroup with that cpu.uclamp.min; prints the median and max burst time. Run on the Chromebook as root in a
# scope: systemd-run -q --scope -p CPUWeight=100 bash burst-latency.sh 40   (then echo 0 > system.slice/cpu.uclamp.min)
v=$1
echo max > /sys/fs/cgroup/system.slice/cpu.uclamp.min
cg=/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)
echo "$v" > $cg/cpu.uclamp.min
ts=()
for i in $(seq 15); do
  sleep 0.6
  a=$(date +%s%N); head -c 4194304 /dev/zero | sha256sum > /dev/null; b=$(date +%s%N)
  ts+=($(( (b-a)/1000000 )))
done
s=$(printf '%s\n' "${ts[@]}" | sort -n)
echo "uclamp.min=$v%: median $(echo "$s" | sed -n 8p) ms, max $(echo "$s" | tail -1) ms (all: ${ts[*]})"
