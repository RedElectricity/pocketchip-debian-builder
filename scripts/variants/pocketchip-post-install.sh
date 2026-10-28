#!/usr/bin/env bash
# Runs inside the armhf chroot, as root, at the end of build-rootfs.sh.
# Extras are staged at /opt/pocketchip-extras by the rootfs script.
set -euo pipefail

user="${1:-chip}"
home="$(getent passwd "$user" | cut -d: -f6)"
extras=/opt/pocketchip-extras

[[ -n "$home" && -d "$home" ]] || { printf 'error: no home for %s\n' "$user" >&2; exit 1; }
[[ -d "$extras" ]] || { printf 'error: missing %s\n' "$extras" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# --- pocketchip-menu as the home screen -------------------------------------
rm -rf "$home/pocketchip-menu"
cp -a "$extras/pocketchip-menu" "$home/pocketchip-menu"
cp -a "$extras/apps/." "$home/pocketchip-menu/apps/"
sed -i "s#/home/chip/pocketchip-menu#$home/pocketchip-menu#g" "$home/pocketchip-menu/load.sh"
chmod 0755 "$home/pocketchip-menu/load.sh"

install -d -m 0755 "$home/.config/awesome"
sed "s#@HOME@#$home#g" "$extras/awesome/rc.lua" > "$home/.config/awesome/rc.lua"
chmod 0644 "$home/.config/awesome/rc.lua"
install -m 0644 "$extras/awesome/blank_ptr.xbm" "$home/.config/awesome/blank_ptr.xbm"

install -m 0755 "$extras/xinitrc-awesome" "$home/.xinitrc"

cat > /usr/local/bin/pocket-home <<EOF
#!/bin/sh
exec "$home/pocketchip-menu/load.sh"
EOF
chmod 0755 /usr/local/bin/pocket-home

# Keep the i3 fallback session usable: point its menu key at the new home.
if [[ -f "$home/.config/i3/config" ]]; then
  sed -i 's#exec --no-startup-id pocketchip-menu$#exec --no-startup-id pocket-home#' \
    "$home/.config/i3/config"
fi

# --- PICO-8 -----------------------------------------------------------------
install -d -m 0755 /usr/lib/pico-8
cp -a "$extras/pico-8/." /usr/lib/pico-8/
install -m 0755 "$extras/bin/pico-8" /usr/local/bin/pico-8

# --- SunVox -----------------------------------------------------------------
install -m 0755 "$extras/sunvox/sunvox_lofi" /usr/local/bin/sunvox

# --- pocketchip-batt --------------------------------------------------------
# Built here so the binary matches the image's libc/X11. The unit is installed
# but left disabled: on a mainline kernel upower already reports the AXP209
# battery, and this daemon writes to the same I2C device.
apt-get update
apt-get install -y --no-install-recommends build-essential libx11-dev libxext-dev
gcc "$extras/batt/pocketchip-one.c" -lX11 -lXext -o /usr/sbin/pocketchip-one
chmod 0755 /usr/sbin/pocketchip-one
apt-get purge -y build-essential libx11-dev libxext-dev
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

install -m 0644 "$extras/batt/pocketchip-one.service" \
  /etc/systemd/system/pocketchip-one.service
cat > /etc/tmpfiles.d/pocketchip-batt.conf <<'EOF'
d /run/pocketchip-batt 0777 root root -
L /usr/lib/pocketchip-batt - - - - /run/pocketchip-batt
EOF

chown -R "$(id -u "$user"):$(id -g "$user")" "$home/pocketchip-menu" \
  "$home/.config/awesome" "$home/.xinitrc"

rm -rf "$extras"

printf 'pocketchip variant installed for %s\n' "$user"
