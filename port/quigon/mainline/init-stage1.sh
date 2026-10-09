#!/bin/sh
# /init of the stage-1 test initramfs (Alpine minirootfs + wpa_supplicant + dropbear). Everything goes to /dev/kmsg,
# so it ends up in console-ramoops, which Omarchy reads from /sys/fs/pstore after the reboot (mainline-log).
# Lines are tagged QM: for grepping.
# With Wi-Fi up it stays reachable over SSH (key-only, root) for up to 20 minutes for live debugging, then reboots;
# without Wi-Fi it reboots after 20 s. The hardware watchdog (30 s) covers a hang either way.
# Build-host-only files, never in the repo: /etc/wpa_supplicant/wpa_supplicant.conf (Wi-Fi credentials) and
# /root/.ssh/authorized_keys.
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
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
k "gpu: $(dmesg | grep -i -E 'panfrost|mali|13000000.gpu|mfgcfg' | tail -10 | tr '\n' ';' | cut -c1-950)"
k "gpu: dri=[$(ls /dev/dri 2>/dev/null | tr '\n' ' ')] devfreq=[$(cat /sys/class/devfreq/*gpu*/cur_freq /sys/class/devfreq/*gpu*/available_frequencies 2>/dev/null | tr '\n' ' ')] mfg_bg3d=$(grep -E ' mfg_bg3d | mfg_sel_mfgpll ' /sys/kernel/debug/clk/clk_summary 2>/dev/null | tr -s ' ' | tr '\n' ';')"
k "gpu: pm domains: $(grep -E 'mfg' /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | tr -s ' ' | tr '\n' ';')"
k "cpufreq: $(for p in /sys/devices/system/cpu/cpufreq/policy*; do echo -n "$(basename $p) $(cat $p/scaling_governor 2>/dev/null) cur=$(cat $p/scaling_cur_freq 2>/dev/null) max=$(cat $p/cpuinfo_max_freq 2>/dev/null); "; done)"
k "gpu: regulators: $(for r in /sys/class/regulator/*; do n=$(cat $r/name 2>/dev/null); case $n in buck_vgpu|ldo_sram_gpu|vproc1|vsram_proc1) echo -n "$n=$(cat $r/microvolts 2>/dev/null)uV/$(cat $r/state 2>/dev/null) ";; esac; done)"
k "pci: $(for d in /sys/bus/pci/devices/*; do [ -e "$d" ] && echo -n "$(basename "$d") $(cat "$d/vendor"):$(cat "$d/device"); "; done)"
k "display: $(dmesg | grep -i -E 'mediatek-drm|mtk-dp|mtk_dp|edp|dvo|mmsys|disp|panel|backlight|fbcon|drm' | grep -v -i panfrost | tail -16 | tr '\n' ';' | cut -c1-950)"
k "display: connectors: $(for c in /sys/class/drm/card*-*; do [ -e "$c/status" ] && echo -n "$(basename $c)=$(cat $c/status)/$(cat $c/enabled 2>/dev/null) modes=[$(tr '\n' ' ' < $c/modes)] "; done) fb=[$(cat /sys/class/graphics/fb0/name /sys/class/graphics/fb0/virtual_size 2>/dev/null | tr '\n' ' ')] backlight=[$(for b in /sys/class/backlight/*; do [ -e "$b" ] && echo -n "$(basename $b) $(cat $b/actual_brightness)/$(cat $b/max_brightness) "; done)]"
k "display: pm domains: $(grep -E 'disp|mm-infra|edp' /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | tr -s ' ' | tr '\n' ';')"
k "display: clocks: $(grep -E ' (mm_disp_ovl0_4l|mm_disp_rdma0|mmsys_0_disp_dvo|mmsys_1_disp_dvo|edp_sel|disp0_sel|tvdpll2) ' /sys/kernel/debug/clk/clk_summary 2>/dev/null | tr -s ' ' | cut -c1-80 | tr '\n' ';')"
k "input: $(grep '^N:' /proc/bus/input/devices | cut -d'"' -f2 | tr '\n' ';') ec: $(dmesg | grep -i -E 'cros-ec|cros_ec|elan|i2c_hid|spi-mt65xx|mtk-spi' | tail -6 | tr '\n' ';' | cut -c1-600)"
k "battery: $(for b in /sys/class/power_supply/*; do [ -e "$b" ] && echo -n "$(basename $b) $(cat $b/status 2>/dev/null) $(cat $b/capacity 2>/dev/null)% "; done)"
k "clk summary lines: $(wc -l < /sys/kernel/debug/clk/clk_summary 2>/dev/null), pm domains: $(grep -c . /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null)"

# Internal storage (UFS) and a GPU test with Omarchy's own Mesa: ROOT-C mounted read-only *without journal replay*
# (noload), so the test kernel never writes to the real install.
i=0; while [ ! -b /dev/sda7 ] && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done

# Hang-proof disk log (see /usr/local/bin/qblk): blk <step> snapshots, blkbg <label> every second.
blk() { qblk "$@"; }
blkbgpid=
blkbg() { blkbgpid=$(qblk -bg "$@"); }
blkbg_stop() { [ -n "$blkbgpid" ] && kill $blkbgpid 2>/dev/null; blkbgpid=; }
blk "start"

# Wi-Fi early, before the risky steps, so the test kernel is reachable over SSH while they run. USB dongle
# (RTL8821AU, rtw88 modules) while PCIe (the internal MT7922) is parked.
netup=
blkbg wifi
for m in rfkill libarc4 cfg80211 mac80211 rtw88_core rtw88_usb rtw88_88xxa rtw88_8821a rtw88_8821au; do
  [ -f /lib/modules/$m.ko ] || continue
  blk "before insmod $m"; insmod /lib/modules/$m.ko; k "wifi: insmod $m -> $?"
done
blk "wifi modules loaded"

i=0; while [ ! -d /sys/class/net/wlan0 ] && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
if [ -d /sys/class/net/wlan0 ] && [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
  ip link set lo up
  ip link set wlan0 up; k "wifi: wlan0 up -> $?"; sleep 2
  timeout 20 iw dev wlan0 scan > /tmp/scan.txt 2>&1
  ssid=$(sed -n 's/^[[:space:]]*ssid="\(.*\)"/\1/p' /etc/wpa_supplicant/wpa_supplicant.conf | head -1)
  # (the network name stays out of the log: only whether it was seen, and on which frequencies)
  k "wifi: scan: $(grep -c '^BSS' /tmp/scan.txt) networks; configured network seen: $(awk -v s="$ssid" '/^BSS/{f=""} /freq:/{f=$2} $1=="SSID:"{sub(/^[ \t]*SSID: /,""); if ($0==s) printf "%s MHz ", f}' /tmp/scan.txt)"
  blk "wlan0 present, starting wpa_supplicant"
  # (Alpine's wpa_supplicant has no -f: run it in the background with its output in /tmp/wpa.log)
  wpa_supplicant -d -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf > /tmp/wpa.log 2>&1 &
  sleep 1; k "wifi: wpa_supplicant $(kill -0 $! 2>/dev/null && echo running || echo exited: $(grep -v -i -E 'psk|ssid' /tmp/wpa.log | tail -3 | tr '\n' ';'))"
  sleep 5; k "wifi: $(grep -E 'CTRL-EVENT-(CONNECTED|DISCONNECTED|SSID-TEMP-DISABLED|ASSOC-REJECT|AUTH-REJECT)|WPA: Key negotiation completed' /tmp/wpa.log | sed -E 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/g; s/ssid=\"[^\"]*\"/ssid=<..>/g' | tail -3 | tr '\n' ';')"; blk "wpa_supplicant started"
  if udhcpc -i wlan0 -r 192.168.0.22 -t 15 -T 2 -n -q -s /usr/share/udhcpc/default.script > /tmp/dhcp.log 2>&1; then
    k "network up: $(ip -4 -o addr show wlan0 | awk '{print $4}') via $(ip route | awk '/default/{print $3}')"
    mkdir -p /etc/dropbear && dropbear -R -E -s -p 22 2>/tmp/dropbear.log && k "ssh (dropbear) listening"
    netup=1; blk "network up"
  else
    k "no DHCP lease: $(tail -3 /tmp/wpa.log | tr '\n' ';') $(tail -2 /tmp/dhcp.log | tr '\n' ';')"
  fi
else
  k "no wlan0 after 15 s: $(dmesg | grep -i -E 'rtw|usb|mt79|pcie|pci ' | tail -6 | tr '\n' ';' | cut -c1-900)"
fi


blkbg_stop
# Display drivers as modules, one at a time, each step logged to disk first (the built-in display froze the SoC).
for m in mtk-mmsys mtk-mutex drm_dma_helper phy-mtk-edp mtk_dp mediatek-drm; do
  [ -f /lib/modules/$m.ko ] || continue
  blk "before insmod $m"; k "display: insmod $m"
  insmod /lib/modules/$m.ko dyndbg=+p; k "display: insmod $m -> $? : $(dmesg | tail -4 | tr '\n' ';' | cut -c1-500)"
  sleep 2; blk "2 s after insmod $m"
done
if [ -f /lib/modules/mediatek-drm.ko ]; then
  sleep 3; blk "display modules loaded"
  for c in /sys/class/drm/card*-*; do [ -e "$c/status" ] && k "display: $(basename $c) status=$(cat $c/status) enabled=$(cat $c/enabled) dpms=$(cat $c/dpms 2>/dev/null) modes=[$(tr '\n' ' ' < $c/modes)]"; done
  for f in /sys/kernel/debug/dri/*/state; do grep -q mediatek "${f%/state}/name" 2>/dev/null || continue
    k "display: drm state: $(grep -E 'crtc\[|plane\[|connector\[|active=|enable=|mode:|fb=|crtc=|size=' $f | tr -s ' \t' ' ' | tr '\n' ';' | cut -c1-950)"; done
  k "display: backlight $(cat /sys/class/backlight/*/bl_power /sys/class/backlight/*/actual_brightness 2>/dev/null | tr '\n' ' ')"
  k "display: after modules: $(dmesg | grep -i -E 'mediatek-drm|mtk-dp|mtk_dp|edp|dvo|mmsys|mutex|panel|fbcon|drm' | grep -v -i panfrost | tail -14 | tr '\n' ';' | cut -c1-950)"
fi
k "ufs: $(dmesg | grep -i -E 'ufs|scsi|sd[a-z]' | tail -8 | tr '\n' ';' | cut -c1-900)"
k "partitions: $(awk 'NR>2{printf "%s(%s) ", $4, $3}' /proc/partitions | cut -c1-500)"
if [ -b /dev/sda7 ] && mount -t ext4 -o ro,noload /dev/sda7 /mnt 2>/tmp/mnt.err; then
  k "ROOT-C mounted read-only: $(head -c 120 /mnt/etc/os-release | tr '\n' ' ')"
  for d in dev proc sys; do mount --bind /$d /mnt/$d; done
  mount -t tmpfs tmpfs /mnt/tmp; mount -t tmpfs tmpfs /mnt/run
  k "gpu test: eglinfo: $(chroot /mnt /usr/bin/eglinfo -B -p surfaceless 2>&1 | grep -i -E 'renderer|version string|vendor' | head -6 | tr '\n' ';' | cut -c1-900)"
  k "gpu test: gles-bench (Panfrost): $(timeout 120 chroot /mnt env BENCH_SURFACELESS=1 /usr/local/bin/gles-bench 2>&1 | tr '\n' ';' | cut -c1-900)"
  k "gpu test: devfreq after: cur=$(cat /sys/class/devfreq/*gpu*/cur_freq 2>/dev/null) trans=$(cat /sys/class/devfreq/*gpu*/trans_stat 2>/dev/null | tail -1); regs: $(for r in /sys/class/regulator/*; do n=$(cat $r/name); case $n in buck_vgpu|ldo_sram_gpu) echo -n "$n=$(cat $r/microvolts) ";; esac; done)"
  k "gpu test: panfrost after: $(dmesg | grep -i panfrost | tail -4 | tr '\n' ';' | cut -c1-600)"
  sync; umount /mnt/run /mnt/tmp /mnt/sys /mnt/proc /mnt/dev; umount /mnt
else
  k "ROOT-C not mounted: $(cat /tmp/mnt.err 2>/dev/null)"
fi

# PCIe controller (module, instrumented with numbered steps: see patches/mainline-pcie-gen3-qstep-debug.patch),
# loaded under a timeout with the disk log running every second; quigon.qdelay=<ms> sets the pause after each step
# (default 1500). If the link comes up, the MT7922 driver (mt7921e) follows.
if [ -f /lib/modules/pcie-mediatek-gen3.ko ] && ! grep -q quigon.pcie=manual /proc/cmdline; then
  qd=$(sed -n 's/.*quigon\.qdelay=\([0-9]*\).*/\1/p' /proc/cmdline); qd=${qd:-1500}
  blkbg pcie; k "pcie: insmod start (qdelay=$qd)"
  insmod /lib/modules/pcie-mediatek-gen3.ko qdelay=$qd &
  ip=$!
  i=0; while kill -0 $ip 2>/dev/null && [ $i -lt 40 ]; do sleep 1; i=$((i+1)); done
  if kill -0 $ip 2>/dev/null; then
    k "pcie: insmod STUCK after 40 s; insmod stack: $(tr '\n' ';' < /proc/$ip/stack 2>/dev/null)"
    blk "pcie stuck"; sync; killall -9 watchdog; sleep 120
  fi
  k "pcie: insmod returned after $i s; devices: $(for d in /sys/bus/pci/devices/*; do [ -e "$d" ] && echo -n "$(basename $d) $(cat $d/vendor):$(cat $d/device); "; done)"
  if [ -d /sys/bus/pci/devices/0000:01:00.0 ]; then
    for m in mt76 mt76-connac-lib mt792x-lib mt7921-common mt7921e; do
      [ -f /lib/modules/$m.ko ] && { insmod /lib/modules/$m.ko; k "pcie: insmod $m -> $?"; }
    done
    sleep 3; k "pcie: wifi: $(ls /sys/class/net | tr '\n' ' ') $(dmesg | grep -i mt7921e | tail -3 | tr '\n' ';' | cut -c1-500)"
  fi
  blk "pcie done"; blkbg_stop
fi

stay=20; [ -n "$netup" ] && stay=1200
# With a working display, say hello on it and stay up a minute so it can be seen.
if [ -e /dev/fb0 ]; then
  printf '\n\n  quigon: mainline %s on the internal display (Panfrost GPU, fbcon)\n\n' "$(uname -r)" > /dev/tty1 2>/dev/null
  k "display: fb0 present, wrote a banner to tty1"; [ -n "$netup" ] || stay=60
fi
k "staying up ${stay} s (touch /tmp/stay-more to extend, /tmp/reboot-now to leave), then reboot"
while [ $stay -gt 0 ] && [ ! -e /tmp/reboot-now ]; do
  sleep 5; stay=$((stay-5))
  [ -e /tmp/stay-more ] && { rm -f /tmp/stay-more; stay=$((stay+1200)); }
done
k "rebooting"; blk "rebooting (clean end)"
sync; reboot -f
