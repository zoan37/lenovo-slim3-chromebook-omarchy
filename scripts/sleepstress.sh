#!/bin/bash
# sleepstress.sh [cycles] [sleep-seconds] [awake-seconds]: repeated s2idle suspend/resume on the Chromebook (root),
# woken by the RTC. After every resume: the suspend counted, Wi-Fi back, the panel connector, the sound card, and
# new kernel warnings/errors. One line per cycle; a summary at the end. Run detached (systemd-run) so a dropped SSH
# session doesn't stop it; with a SuzyQ attached the AP console shows where a hang stopped.
N=${1:-20}; S=${2:-15}; A=${3:-10}
st() { cat /sys/power/suspend_stats/$1; }
bad='Oops|BUG:|WARNING:|SError|Unable to handle|timed out|timeout|failed|error -|Internal error'
pass=0; fail=0
echo "$(date +%T) sleepstress: $N cycles, ${S}s asleep, ${A}s awake; kernel $(uname -r)"
for i in $(seq 1 "$N"); do
  s0=$(st success); f0=$(st fail); d0=$(dmesg | wc -l); t0=$(date +%s)
  echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +"$S" > /sys/class/rtc/rtc0/wakealarm
  echo "sleepstress $i/$N $(date +%T)" > /dev/ttyS0 2>/dev/null
  systemctl suspend
  for _ in $(seq 60); do (( $(st success) > s0 || $(st fail) > f0 )) && break; sleep 1; done
  slept=$(( $(date +%s) - t0 ))
  wifi=no; for _ in $(seq 25); do nmcli -t -f DEVICE,STATE device | grep -q ':connected$' && { wifi=yes; break; }; sleep 1; done
  edp=$(cat /sys/class/drm/card*-eDP-1/status 2>/dev/null | head -1)
  snd=$(grep -c . /proc/asound/cards)
  errs=$(dmesg | tail -n +$((d0 + 1)) | grep -E "$bad" | grep -v -E "ASoC: no backend|Failed to do AUX transfer" | head -3 | tr '\n' '|')
  ok=yes; (( $(st success) > s0 )) || ok=no; (( $(st fail) > f0 )) && ok=no
  [[ $wifi == yes && $edp == connected && $snd -gt 0 && -z $errs ]] || ok=no
  [[ $ok == yes ]] && pass=$((pass + 1)) || fail=$((fail + 1))
  echo "$(date +%T) cycle $i: ok=$ok slept~${slept}s suspend=$(st success)/$(st fail) wifi=$wifi edp=$edp snd=$snd ${errs:+errs=$errs}"
  sleep "$A"
done
echo "$(date +%T) sleepstress done: $pass passed, $fail failed"
