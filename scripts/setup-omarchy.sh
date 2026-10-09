#!/bin/bash
# Run on the booted Arch system as root after `omarchy` + omarchy-base.packages are installed.
# Creates the desktop user, applies the parts of Omarchy's system setup that fit this machine, and
# finalizes the user. Env: DESKTOP_USER (required), PUBKEY (optional ssh key for the user).
# Skipped on purpose: post-install/pacman.sh (would install Omarchy's x86 pacman.conf over Arch Linux ARM's),
# docker.sh / snapper.sh (not installed), firewall.sh + NetworkManager + sddm (would cut SSH/bridge access or
# need a VT; handled separately).
set -uo pipefail
U=${DESKTOP_USER:?}
export OMARCHY_PATH=/usr/share/omarchy OMARCHY_INSTALL=/usr/share/omarchy/install
export PATH=$OMARCHY_PATH/bin:$PATH
run_logged() { echo "-- $1"; [[ -f $1 ]] || { echo "   (missing)"; return; }; bash -eE -c 'source "$1"' bash "$1" || echo "   FAILED: $1"; }

pacman -Q sudo >/dev/null 2>&1 || pacman -S --noconfirm sudo
id "$U" >/dev/null 2>&1 || useradd -m -G wheel,seat,video,input,render -s /bin/bash "$U"
echo "$U:omarchy" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
if [[ -n ${PUBKEY:-} ]]; then
  install -d -m 700 -o "$U" -g "$U" /home/$U/.ssh
  echo "$PUBKEY" > /home/$U/.ssh/authorized_keys; chown "$U:$U" /home/$U/.ssh/authorized_keys; chmod 600 /home/$U/.ssh/authorized_keys
fi

for s in theme-system browser-policy increase-lockout-limit lockscreen-pam fix-powerprofilesctl-shebang ssh-command-path ssh-keepalive; do
  run_logged $OMARCHY_INSTALL/config/$s.sh
done
systemctl enable cups.service avahi-daemon.service systemd-resolved.service power-profiles-daemon.service systemd-oomd.service 2>&1 | grep -v "^Created symlink" || true
for s in set-wireless-regdom bluetooth; do run_logged $OMARCHY_INSTALL/hardware/$s.sh; done
for s in udev localdb; do run_logged $OMARCHY_INSTALL/post-install/$s.sh; done

loginctl enable-linger "$U"
uid=$(id -u "$U")
for i in $(seq 20); do [[ -d /run/user/$uid ]] && break; sleep 0.5; done
# provision-owner context: first-install semantics (migrations marked done) but Node.js from the network,
# since there is no ISO-bundled tarball (and it would be x64 anyway).
echo "-- omarchy-provision-user --first-install as $U"
runuser -u "$U" -- env HOME=/home/$U USER=$U XDG_RUNTIME_DIR=/run/user/$uid OMARCHY_PATH=$OMARCHY_PATH \
  OMARCHY_SETUP_CONTEXT=provision-owner PATH=$OMARCHY_PATH/bin:/usr/local/bin:/usr/bin bash -lc 'cd ~ && omarchy-provision-user --first-install' 2>&1 | tail -25
