#!/bin/bash
# Build a bootable Arch Linux ARM USB stick for the quigon Chromebook, from ChromeOS developer mode, as root.
# Reuses the running ChromeOS kernel (re-signed with the devkeys, new command line), its modules and firmware.
# Env: DEV=/dev/sdX (must be a removable USB disk), B=<bridge url> (serves files/ArchLinuxARM-aarch64-latest.tar.gz),
#      PUBKEY=<ssh public key line>. Runs on the Chromebook; erases $DEV.
set -euo pipefail
DEV=${DEV:?}; B=${B:?}
name=$(basename "$DEV")
[ "$(cat /sys/block/$name/removable)" = 1 ] || { echo "$DEV is not removable"; exit 1; }
readlink -f /sys/block/$name | grep -q /usb || { echo "$DEV is not on USB"; exit 1; }
[ "$(rootdev -s -d)" != "$DEV" ] || { echo "$DEV is the ChromeOS disk"; exit 1; }
M=/usr/local/alarm-root
KVER=$(uname -r)
CMDLINE="console= loglevel=7 init=/sbin/init root=PARTUUID=%U/PARTNROFF=1 rootwait rw noinitrd net.ifnames=0 lsm=capability,landlock,yama,bpf cpuidle.governor=teo irqchip.gicv3_pseudo_nmi=1"

echo "== USB boot flag"
crossystem dev_boot_usb=1
crossystem dev_boot_usb

echo "== partition $DEV"
for p in ${DEV}?*; do umount "$p" 2>/dev/null || true; done
[ "$(blockdev --getss $DEV)" = 512 ] || { echo "unexpected sector size"; exit 1; }
total=$(blockdev --getsz $DEV)
cgpt create $DEV
cgpt boot -p $DEV
cgpt add -i 1 -t kernel -b 8192 -s 65536 -l KERN-A -S 1 -T 5 -P 10 $DEV
cgpt add -i 2 -t data -b 73728 -s $((total - 73728 - 2048)) -l ROOT $DEV
blockdev --rereadpt $DEV; sleep 2
cgpt show $DEV
mkfs.ext4 -q -F -L ALARM ${DEV}2

echo "== extract Arch Linux ARM"
mkdir -p $M; mount ${DEV}2 $M
curl -sf "$B/files/ArchLinuxARM-aarch64-latest.tar.gz" | bsdtar -xpf - -C $M
sync; du -sh $M

echo "== ChromeOS kernel modules + firmware"
cp -a /lib/modules/$KVER $M/usr/lib/modules/
mkdir -p $M/usr/lib/firmware/updates
cp -a /lib/firmware/. $M/usr/lib/firmware/updates/

echo "== base config"
echo quigon > $M/etc/hostname
mkdir -p $M/var/log/journal
cat > $M/etc/systemd/network/wlan.network <<'NET'
[Match]
Name=wlan*

[Network]
DHCP=yes
NET
install -d -m 700 $M/root/.ssh
echo "${PUBKEY:?}" > $M/root/.ssh/authorized_keys; chmod 600 $M/root/.ssh/authorized_keys
install -d -m 700 -o 1000 -g 1000 $M/home/alarm/.ssh
echo "$PUBKEY" > $M/home/alarm/.ssh/authorized_keys; chown 1000:1000 $M/home/alarm/.ssh/authorized_keys; chmod 600 $M/home/alarm/.ssh/authorized_keys

echo "== Wi-Fi from the ChromeOS saved network (not printed)"
prof=/var/cache/shill/default.profile
ssid=$(sed -n '/^\[wifi_/,/^\[/{s/^Name=//p}' $prof | head -1)
[ -n "$ssid" ] || ssid=$(sed -n 's/^\[wifi_any_\([0-9a-f]*\)_.*/\1/p' $prof | head -1 | sed "s/../\\\\x&/g" | xargs -0 printf "%b")
psk=$(sed -n '/^\[wifi_/,/^\[/{s/^WiFi.Passphrase=//p}' $prof | head -1)
case "$psk" in rot47:*) psk=$(printf '%s' "${psk#rot47:}" | tr '!-~' 'P-~!-O');; esac
install -d -m 755 $M/etc/wpa_supplicant
umask 077
{ echo "ctrl_interface=/run/wpa_supplicant"; echo "update_config=1"; echo "network={"; printf '  ssid="%s"\n' "$ssid"; printf '  psk="%s"\n' "$psk"; echo "}"; } > $M/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
umask 022
echo "ssid length ${#ssid}, passphrase length ${#psk}"

echo "== chroot: install wpa_supplicant"
mount --bind /proc $M/proc; mount --bind /sys $M/sys; mount --bind /dev $M/dev; mount -t tmpfs tmpfs $M/tmp
mv $M/etc/resolv.conf $M/etc/resolv.conf.orig 2>/dev/null || true
cp /etc/resolv.conf $M/etc/resolv.conf
chroot $M /bin/bash -c 'pacman-key --init >/dev/null 2>&1 && pacman-key --populate archlinuxarm >/dev/null 2>&1 && pacman -Sy --noconfirm --needed wpa_supplicant 2>&1 | tail -3'
chroot $M systemctl enable wpa_supplicant@wlan0.service systemd-timesyncd.service systemd-resolved.service 2>&1 | tail -2
chroot $M gpgconf --kill all 2>/dev/null || true
for p in /proc/[0-9]*; do [ "$(readlink $p/root)" = "$M" ] && kill ${p#/proc/} 2>/dev/null || true; done; sleep 1
if [ -L $M/etc/resolv.conf.orig ] || [ -e $M/etc/resolv.conf.orig ]; then rm -f $M/etc/resolv.conf; mv $M/etc/resolv.conf.orig $M/etc/resolv.conf; fi
for d in tmp dev sys proc; do mountpoint -q $M/$d && umount $M/$d; done

echo "== bridge agent service"
cat > $M/usr/local/bin/cbridge-agent <<AG
#!/bin/bash
B=$B
while :; do
  curl -sf -m 15 -o /tmp/qc "\$B/cmd" || { sleep 3; continue; }
  [ -s /tmp/qc ] || { sleep 1; continue; }
  id=\$(head -1 /tmp/qc); { echo "B=\$B"; tail -n +2 /tmp/qc; } > /tmp/qc.sh
  (cd /tmp; timeout 3600 bash /tmp/qc.sh) > /tmp/qc.out 2>&1; echo "[exit \$?]" >> /tmp/qc.out
  curl -sf -m 120 --data-binary @/tmp/qc.out "\$B/out?id=\$id" >/dev/null
done
AG
chmod 755 $M/usr/local/bin/cbridge-agent
cat > $M/etc/systemd/system/cbridge.service <<'UNIT'
[Unit]
Description=LAN command bridge agent
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/cbridge-agent
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/cbridge.service $M/etc/systemd/system/multi-user.target.wants/cbridge.service
sync; umount $M

echo "== kernel"
dd if=$(rootdev -s -d)2 of=/tmp/kern-a.bin bs=1M status=none
echo "$CMDLINE" > /tmp/cmdline
futility vbutil_kernel --repack /tmp/kern-usb.bin --oldblob /tmp/kern-a.bin \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --config /tmp/cmdline
futility vbutil_kernel --verify /tmp/kern-usb.bin | grep -E "Keyblock|Flags|Config|console" | head -6
dd if=/tmp/kern-usb.bin of=${DEV}1 bs=1M conv=fsync status=none
sync
echo "== done"
