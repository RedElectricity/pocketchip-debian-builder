#!/usr/bin/env bash
# Runs inside the armhf chroot, as root, at the end of build-rootfs.sh.
set -euo pipefail

user="${1:-chip}"
home="$(getent passwd "$user" | cut -d: -f6)"
extras=/opt/pocketchip-extras

[[ -n "$home" && -d "$home" ]] || { printf 'error: no home for %s\n' "$user" >&2; exit 1; }
[[ -d "$extras" ]] || { printf 'error: missing %s\n' "$extras" >&2; exit 1; }

install -m 0755 "$extras/xinitrc-xfce" "$home/.xinitrc"

# --- CH7033 HDMI bridge -----------------------------------------------------
# The Debian armmp config leaves CONFIG_DRM_I2C_CH7033 unset, so build the
# upstream driver as an out-of-tree module against the matching kernel headers.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential linux-headers-armmp

# Installing the headers meta package can pull a newer linux-image-armmp than
# the one mmdebstrap installed, because trixie keeps only the current kernel.
# Build against the newest kernel in /boot, not whatever happens to be first
# in /lib/modules.
kver="$(basename "$(ls -1 /boot/vmlinuz-* | sort -V | tail -1)")"
kver="${kver#vmlinuz-}"
[[ -n "$kver" ]] || { printf 'error: no kernel in /boot\n' >&2; exit 1; }
if [[ ! -e "/lib/modules/$kver/build" ]]; then
  apt-get install -y --no-install-recommends "linux-headers-$kver"
fi
[[ -e "/lib/modules/$kver/build" ]] ||
  { printf 'error: no headers for %s\n' "$kver" >&2; exit 1; }

cat > "$extras/ch7033/Makefile" <<'EOF'
obj-m += ch7033.o
EOF
make -C "/lib/modules/$kver/build" M="$extras/ch7033" modules
install -d "/lib/modules/$kver/updates"
install -m 0644 "$extras/ch7033/ch7033.ko" \
  "/lib/modules/$kver/updates/ch7033.ko"
depmod -a "$kver"
printf 'ch7033\n' > /etc/modules-load.d/ch7033.conf

apt-get purge -y build-essential linux-headers-armmp
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*
update-initramfs -u -k all

# The PocketCHIP console keymap is for the TCA8418 matrix keyboard. A desktop
# CHIP uses a USB keyboard, which must keep the default layout.
ln -sfn /dev/null /etc/systemd/system/pocketchip-keymap.service

# No resistive touch panel on a desktop CHIP.
rm -f /etc/X11/xorg.conf.d/40-pocketchip-touch.conf

chown "$(id -u "$user"):$(id -g "$user")" "$home/.xinitrc"

rm -rf "$extras"

printf 'desktop variant installed for %s\n' "$user"
