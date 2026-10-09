#!/bin/sh
# /init of the stage-1 test initramfs (Alpine minirootfs + wpa_supplicant + dropbear). Everything goes to /dev/kmsg,
# so it ends up in console-ramoops, which Omarchy reads from /sys/fs/pstore after the reboot (mainline-log).
# Lines are tagged QM: for grepping.
# With Wi-Fi up it stays reachable over SSH (key-only, root) for up to 20 minutes for live debugging, then reboots;
# without Wi-Fi it reboots after 20 s. The hardware watchdog (30 s) covers a hang either way.
# Build-host-only files, never in the repo: /etc/wpa_supplicant/wpa_supplicant.conf (Wi-Fi credentials) and
# /root/.ssh/authorized_keys.
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
mkdir -p /dev/pts /run /tmp; mount -t devpts devpts /dev/pts; mount -t tmpfs tmpfs /run; mount -t tmpfs tmpfs /tmp
k() { echo "QM: $*" > /dev/kmsg; }
k "init reached: $(uname -r) $(cat /proc/cmdline)"
if [ -e /dev/watchdog ]; then watchdog -T 30 -t 5 /dev/watchdog && k "watchdog armed (30 s)"; else k "no /dev/watchdog"; fi
k "wdt: $(dmesg | grep -i -E 'mtk-wdt|watchdog' | tail -4 | tr '\n' ';' | cut -c1-600)"
if grep -q quigon.wdtest /proc/cmdline; then
  # Watchdog self-test: stop feeding it. A working reset reboots us within the timeout (31 s).
  k "wdtest: killing the watchdog feeder at $(cut -d. -f1 /proc/uptime) s"
  killall -9 watchdog
  sleep 120
  k "wdtest: STILL ALIVE 120 s later at $(cut -d. -f1 /proc/uptime) s -> the watchdog reset does NOT work"
  sync; reboot -f
fi
k "cpus online $(cat /sys/devices/system/cpu/online), $(grep MemTotal /proc/meminfo)"
k "model: $(tr -d '\0' < /proc/device-tree/model)"
k "deferred: $(tr '\n' ';' < /sys/kernel/debug/devices_deferred 2>/dev/null | cut -c1-900)"
for d in /sys/bus/platform/drivers/*/; do
  n=$(ls "$d" | grep -c '^[0-9a-f]*\.') ; [ "$n" -gt 0 ] && echo -n "$(basename "$d")=$n "
done > /tmp/bound; k "bound: $(cut -c1-900 /tmp/bound)"
k "regulators: $(ls /sys/class/regulator | wc -l): $(cat /sys/class/regulator/*/name 2>/dev/null | tr '\n' ' ' | cut -c1-700)"
k "pci: $(for d in /sys/bus/pci/devices/*; do [ -e "$d" ] && echo -n "$(basename "$d") $(cat "$d/vendor"):$(cat "$d/device"); "; done)"
k "clk summary lines: $(wc -l < /sys/kernel/debug/clk/clk_summary 2>/dev/null), pm domains: $(grep -c . /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null)"

# PCIe controller: loaded here under a timeout, with the driver's debug messages on. If the probe doesn't return,
# record where every CPU is and stop feeding the watchdog: the reset keeps pstore (a power-off wouldn't).
if [ -f /lib/modules/pcie-mediatek-gen3.ko ]; then
  echo 9 > /proc/sys/kernel/printk
  k "pcie: insmod start"
  insmod /lib/modules/pcie-mediatek-gen3.ko dyndbg=+p &
  ip=$!
  i=0; while kill -0 $ip 2>/dev/null && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
  if kill -0 $ip 2>/dev/null; then
    k "pcie: insmod STUCK after 15 s; insmod stack: $(tr '\n' ';' < /proc/$ip/stack 2>/dev/null)"
    echo l > /proc/sysrq-trigger; sleep 1; echo w > /proc/sysrq-trigger; sleep 1
    k "pcie: stopping the watchdog feeder -> reset in ~31 s"
    sync; killall -9 watchdog; sleep 120
  fi
  k "pcie: insmod returned after $i s: $(dmesg | grep -i -E 'mtk-pcie|pcie|tphy' | tail -8 | tr '\n' ';' | cut -c1-900)"
fi

stay=20
i=0; while [ ! -d /sys/class/net/wlan0 ] && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
if [ -d /sys/class/net/wlan0 ] && [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
  ip link set lo up
  wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -f /tmp/wpa.log
  if udhcpc -i wlan0 -r 192.168.0.22 -t 15 -T 2 -n -q -s /usr/share/udhcpc/default.script > /tmp/dhcp.log 2>&1; then
    k "network up: $(ip -4 -o addr show wlan0 | awk '{print $4}') via $(ip route | awk '/default/{print $3}')"
    mkdir -p /etc/dropbear && dropbear -R -E -s -p 22 2>/tmp/dropbear.log && k "ssh (dropbear) listening"
    stay=1200
  else
    k "no DHCP lease: $(tail -3 /tmp/wpa.log | tr '\n' ';') $(tail -2 /tmp/dhcp.log | tr '\n' ';')"
  fi
else
  k "no wlan0 after 15 s: $(dmesg | grep -i -E 'mt79|pcie|pci ' | tail -6 | tr '\n' ';' | cut -c1-900)"
fi
k "staying up ${stay} s (touch /tmp/stay-more to extend, /tmp/reboot-now to leave), then reboot"
while [ $stay -gt 0 ] && [ ! -e /tmp/reboot-now ]; do
  sleep 5; stay=$((stay-5))
  [ -e /tmp/stay-more ] && { rm -f /tmp/stay-more; stay=$((stay+1200)); }
done
k "rebooting"
sync; reboot -f
