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

install -d -m 0755 "$home/.config/lxpanel/LXDE/panels"
install -m 0644 "$extras/lxde/panel" "$home/.config/lxpanel/LXDE/panels/panel"
install -m 0644 "$extras/lxde/gtkrc-2.0" "$home/.gtkrc-2.0"
install -d -m 0755 "$home/.config/gtk-3.0"
install -m 0644 "$extras/lxde/settings.ini" "$home/.config/gtk-3.0/settings.ini"
install -m 0644 "$extras/lxde/gtk.css" "$home/.config/gtk-3.0/gtk.css"

# Openbox takes the titlebar button size from the xbm masks; the PocketCHIP
# theme ships 24x24 ones so close/maximize/iconify stay tappable.
install -d -m 0755 /usr/share/themes
cp -a "$extras/lxde/themes/PocketCHIP" /usr/share/themes/

install -d -m 0755 /usr/share/applications
install -m 0644 "$extras/lxde/applications/"*.desktop /usr/share/applications/

# Openbox reads a single rc.xml, so start from the packaged default (keeping
# its keybindings) and switch the theme, touch-sized titlebar layout and the
# drag/double-click thresholds. The default titlebar has 8 px buttons.
if [ -f /etc/xdg/openbox/rc.xml ]; then
  install -d -m 0755 "$home/.config/openbox"
  for source in /etc/xdg/openbox/lxde-rc.xml /etc/xdg/openbox/rc.xml; do
    [ -f "$source" ] || continue
    target="$home/.config/openbox/$(basename "$source")"
    sed \
      -e 's|<name>Clearlooks</name>|<name>PocketCHIP</name>|' \
      -e 's|<titleLayout>NLIMC</titleLayout>|<titleLayout>NIMC</titleLayout>|' \
      -e 's|<dragThreshold>8</dragThreshold>|<dragThreshold>12</dragThreshold>|' \
      -e 's|<doubleClickTime>200</doubleClickTime>|<doubleClickTime>350</doubleClickTime>|' \
      -e 's|<name>sans</name>|<name>Terminus</name>|g' \
      -e 's|<size>8</size>|<size>10</size>|g' \
      -e 's|<size>9</size>|<size>10</size>|g' \
      "$source" > "$target"
    grep -q '<name>PocketCHIP</name>' "$target" || {
      printf 'error: could not select the PocketCHIP Openbox theme in %s\n' "$source" >&2
      exit 1
    }
  done
fi

# LXDE starts the desktop instance with --profile LXDE, so mirror the file
# manager defaults there as well (single click, 480x252 windows) and point the
# desktop at the shipped wallpaper.
install -d -m 0755 "$home/.config/pcmanfm/LXDE" "$home/Pictures"
install -m 0644 "$extras/lxde/pocketchip-wallpaper.png" \
  "$home/Pictures/pocketchip-wallpaper.png"
if [ -f "$home/.config/pcmanfm/default/pcmanfm.conf" ]; then
  install -m 0644 "$home/.config/pcmanfm/default/pcmanfm.conf" \
    "$home/.config/pcmanfm/LXDE/pcmanfm.conf"
fi
cat >> "$home/.config/pcmanfm/LXDE/pcmanfm.conf" <<EOF

[desktop]
wallpaper_mode=stretch
wallpaper_common=0
wallpaper=$home/Pictures/pocketchip-wallpaper.png
desktop_bg=#32302f
desktop_fg=#ebdbb2
desktop_shadow=#000000
show_wallpaper=1
show_documents=0
show_trash=1
show_mounts=1
EOF

install -m 0755 "$extras/xinitrc-lxde" "$home/.xinitrc"
install -m 0755 "$extras/bin/pocketchip-screenshot" \
  /usr/local/bin/pocketchip-screenshot

# Debian 13's lxde-common ships neither /usr/bin/startlxde nor an LXDE
# session profile, so install both here. Without the profile lxsession starts
# no window manager and Xorg shows only its root window.
install -m 0755 "$extras/lxde/startlxde" /usr/local/bin/startlxde
install -d -m 0755 /etc/xdg/lxsession/LXDE
install -m 0644 "$extras/lxde/lxsession-desktop.conf" \
  /etc/xdg/lxsession/LXDE/desktop.conf
install -m 0644 "$extras/lxde/lxsession-autostart" \
  /etc/xdg/lxsession/LXDE/autostart

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
gcc -std=gnu11 "$extras/batt/pocketchip-one.c" -lX11 -lXext \
  -o /usr/sbin/pocketchip-one
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

chown -R "$(id -u "$user"):$(id -g "$user")" \
  "$home/.config/lxpanel" "$home/.config/gtk-3.0" "$home/.config/pcmanfm" \
  "$home/.config/openbox" "$home/Pictures" "$home/.gtkrc-2.0" "$home/.xinitrc"

rm -rf "$extras"

printf 'pocketchip variant installed for %s\n' "$user"
