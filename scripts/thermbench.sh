#!/bin/bash
# thermbench.sh <seconds>: all-core load (openssl sha512 per CPU, 10 s chunks) while sampling temperatures, clocks and
# thermal cooling state every 5 s. Per-chunk throughput on each CPU shows any slowdown over time.
dur=${1:-300}; out=/tmp/thermbench; rm -rf $out; mkdir -p $out
end=$(( $(date +%s) + dur ))
pids=()
for c in 0 1 2 3 4 5 6 7; do
  ( while [ $(date +%s) -lt $end ]; do
      r=$(taskset -c $c openssl speed -seconds 10 -bytes 16384 sha512 2>/dev/null | tail -1 | awk "{print \$NF}")
      echo "$(date +%s) $r" >> $out/cpu$c
    done ) &
  pids+=($!)
done
Z=/sys/class/thermal
t() { cat $Z/thermal_zone$1/temp; }
mx() { local m=0 v; for z in "$@"; do v=$(t $z); [ $v -gt $m ] && m=$v; done; echo $((m/1000)); }
echo "time  big  little soc  gpu  f_little f_big  cdev(l,b,g)" > $out/samples
start=$(date +%s)
while [ $(date +%s) -lt $end ]; do
  printf "%4d  %3d  %3d    %3d  %3d  %5d    %5d  %s,%s,%s\n" $(( $(date +%s)-start )) $(mx 6 7 8 9) $(mx 10 11 12 13 14 15 16 17) $(mx 0 1 2 3) $(mx 4 5) \
    $(( $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)/1000 )) $(( $(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq)/1000 )) \
    $(cat $Z/cooling_device0/cur_state) $(cat $Z/cooling_device1/cur_state) $(cat $Z/cooling_device2/cur_state) >> $out/samples
  sleep 5
done
wait "${pids[@]}"
echo done >> $out/samples
