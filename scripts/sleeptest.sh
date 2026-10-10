#!/bin/bash
# s2idle suspend/resume test: RTC wake after N seconds, then check the desktop came back.
N=${1:-30}
# the smart battery: sbs-10-000b on the ChromeOS kernel, sbs-4-000b on mainline (I2C bus numbering)
B=$(ls -d /sys/class/power_supply/sbs-* 2>/dev/null | head -1)
log() { echo "$(date +%T) $*"; }
U=${DESKTOP_USER:-$(systemctl list-units --plain --no-legend "quigon-desktop@*" | sed -n "s/^quigon-desktop@\(.*\)\.service.*/\1/p" | head -1)}; uid=$(id -u "$U"); sig=$(ls -t /run/user/$uid/hypr | head -1)
E="env XDG_RUNTIME_DIR=/run/user/$uid HYPRLAND_INSTANCE_SIGNATURE=$sig DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus PATH=/usr/share/omarchy/bin:/usr/bin"
e0=$(cat $B/energy_now); t0=$(date +%s.%N); s0=$(cat /sys/power/suspend_stats/success 2>/dev/null)
log "before: energy=${e0}uWh battery=$(cat $B/capacity)% status=$(cat $B/status) suspend_success=$s0"
echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$N > /sys/class/rtc/rtc0/wakealarm
log "wakealarm set: $(cat /sys/class/rtc/rtc0/wakealarm) (now $(date +%s))"
systemctl suspend
sleep 3   # returns when the suspend job is queued; give it time to actually go down and come back
for i in $(seq 60); do (( $(cat /sys/power/suspend_stats/success 2>/dev/null) > s0 )) && break; sleep 1; done
t1=$(date +%s.%N); e1=$(cat $B/energy_now)
log "after: suspend_success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail) last_failed_dev=$(cat /sys/power/suspend_stats/last_failed_dev 2>/dev/null)"
log "elapsed $(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.1f", b-a}')s, energy used $(( (e0-e1)/1000 ))mWh, battery=$(cat $B/capacity)%"
sleep 12
log "wifi: $(nmcli -t -f DEVICE,STATE device | grep ^wlan0) ; ping laptop: $(ping -c2 -W2 192.168.0.29 >/dev/null && echo ok || echo FAIL)"
p=$(pgrep -x Hyprland); log "Hyprland: pid=$p libmali=$(grep -c libmali /proc/$p/maps 2>/dev/null)  bar: $(pgrep -cx quickshell)"
log "locked: $(runuser -u "$U" -- $E omarchy-shell lock isLocked 2>/dev/null)"
log "speaker sink: $(runuser -u "$U" -- $E wpctl status 2>/dev/null | sed -n '/Sinks:/,/Sources:/p' | grep -c Speaker)"
log "palm filter: $(systemctl is-active quigon-palm-filter)"
journalctl -k -b --since "-2min" --no-pager | grep -iE "PM: suspend|PM: resume|Freezing|Restarting|error|fail|timeout" | grep -viE "mtk_memif|sx9324" | tail -15
