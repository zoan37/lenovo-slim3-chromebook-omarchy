#!/bin/bash
# wifips.sh <rounds>: fresh HTTPS requests after 4 s idle (like clicking a link after reading), Wi-Fi power save
# on vs off alternating; prints the median connect / TLS / first-byte times for each.
n=${1:-10}; dev=wlan0; url=https://www.google.com/generate_204
declare -A T
for r in $(seq $n); do
  for ps in on off; do
    iw dev $dev set power_save $ps; sleep 4
    T[$ps]+="$(curl -s -o /dev/null -w '%{time_connect} %{time_appconnect} %{time_starttransfer}' $url)"$'\n'
  done
done
iw dev $dev set power_save on
for ps in on off; do
  echo "power_save=$ps: median connect/TLS/first byte (ms): $(echo -n "${T[$ps]}" | awk '{c[NR]=$1*1000; t[NR]=$2*1000; f[NR]=$3*1000} END {n=asort(c); asort(t); asort(f); m=int((n+1)/2); printf "%.0f / %.0f / %.0f", c[m], t[m], f[m]}')"
done
