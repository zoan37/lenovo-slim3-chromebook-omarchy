#!/bin/bash
# Move Wi-Fi from the bring-up stack (wpa_supplicant@wlan0 + systemd-networkd) to NetworkManager, as Omarchy's
# hardware/network.sh + enable-services.sh would, keeping the same saved network. Rolls back automatically if
# CHECK_HOST isn't reachable within 90 s, so a failed switch doesn't strand a headless machine.
# Run detached (systemd-run) as root. Env: CHECK_HOST (an address on the LAN that answers ping).
set -u
CHECK_HOST=${CHECK_HOST:?}
log() { echo "$(date +%T) $*"; }
conf=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
ssid=$(sed -n 's/^[[:space:]]*ssid="\(.*\)"$/\1/p' $conf | head -1)
psk=$(sed -n 's/^[[:space:]]*psk="\(.*\)"$/\1/p' $conf | head -1)
[[ -n $ssid && -n $psk ]] || { log "no saved network in $conf"; exit 1; }

nmc=/etc/NetworkManager/system-connections/home-wifi.nmconnection
install -d -m 700 /etc/NetworkManager/system-connections
umask 077
cat > $nmc <<NM
[connection]
id=home-wifi
type=wifi
interface-name=wlan0
autoconnect=true

[wifi]
mode=infrastructure
ssid=$ssid
cloned-mac-address=permanent

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=auto

[ipv6]
method=auto
NM
umask 022
chmod 600 $nmc

log "stopping bring-up network stack"
systemctl stop wpa_supplicant@wlan0.service systemd-networkd.service systemd-networkd.socket 2>/dev/null
ip addr flush dev wlan0 2>/dev/null
log "starting NetworkManager"
systemctl start NetworkManager.service

ok=0
for i in $(seq 90); do
  if ping -c1 -W1 "$CHECK_HOST" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done

if (( ok )); then
  log "NetworkManager is online after ${i}s; making it permanent"
  systemctl disable wpa_supplicant@wlan0.service 2>/dev/null
  for unit in systemd-networkd.service systemd-networkd.socket systemd-networkd-varlink.socket \
      systemd-networkd-varlink-metrics.socket systemd-networkd-resolve-hook.socket; do
    systemctl disable "$unit" 2>/dev/null
  done
  systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service 2>/dev/null
  systemctl enable NetworkManager.service 2>/dev/null
  mkdir -p /etc/systemd/network/retired && mv /etc/systemd/network/wlan.network /etc/systemd/network/retired/ 2>/dev/null
  nmcli -t -f DEVICE,STATE,CONNECTION device | grep wlan0
  ip -4 -br addr show wlan0
else
  log "NetworkManager did not reach $CHECK_HOST in 90s; rolling back"
  nmcli -t -f DEVICE,STATE,CONNECTION device 2>&1 | head -5
  systemctl stop NetworkManager.service
  systemctl start systemd-networkd.service wpa_supplicant@wlan0.service
  log "rolled back"
fi
