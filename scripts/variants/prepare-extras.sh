#!/usr/bin/env bash
# Stage everything a variant needs inside the image.
#
# Runs on the build host (not in the chroot) and writes to $2. The rootfs build
# copies that directory to /opt/pocketchip-extras and the variant post-install
# script moves the pieces into place.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
variant="${1:?usage: prepare-extras.sh <pocketchip|desktop> [outdir]}"
out="${2:-$repo_root/build/extras}"

batt_repo="${BATT_REPO:-https://github.com/aleh/pocketchip-batt.git}"
batt_ref="${BATT_REF:-}"
pico8_url="${PICO8_URL:-https://www.lexaloffle.com/dl/chip/pico-8_0.2.4_chip.zip}"
sunvox_url="${SUNVOX_URL:-https://warmplace.ru/soft/sunvox/sunvox-2.1.4d.zip}"
# Match the driver to the default trixie kernel series (6.12). Override
# CH7033_URL when building against a different kernel.
ch7033_url="${CH7033_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/gpu/drm/bridge/chrontel-ch7033.c?h=v6.12}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

fetch() {
  curl -fL --retry 4 --retry-delay 5 --retry-all-errors \
    --connect-timeout 20 -o "$2" "$1"
}

clone_repo() {
  git clone --depth 1 "$1" "$2"
  if [[ -n "$3" ]]; then
    git -C "$2" fetch --depth 1 origin "$3"
    git -C "$2" checkout --detach FETCH_HEAD
  fi
}

case "$variant" in
  pocketchip|desktop) ;;
  *) die "unknown variant: $variant" ;;
esac

rm -rf "$out"
mkdir -p "$out"

if [[ "$variant" == desktop ]]; then
  install -m 0755 "$repo_root/configs/variants/xinitrc-xfce" "$out/xinitrc-xfce"

  # Debian's armmp kernel does not enable CONFIG_DRM_I2C_CH7033, which the CHIP
  # HDMI adapter needs. Build the in-tree driver out-of-tree against the
  # installed kernel headers during post-install.
  install -d "$out/ch7033"
  fetch "$ch7033_url" "$out/ch7033/ch7033.c"
  head -n 1 "$out/ch7033/ch7033.c" | grep -q 'SPDX' ||
    die "unexpected ch7033 source: $ch7033_url"

  printf 'prepared desktop extras in %s\n' "$out"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

install -d "$out/lxde/applications"
install -m 0644 "$repo_root/configs/variants/lxpanel-panel" "$out/lxde/panel"
install -m 0755 "$repo_root/configs/variants/xinitrc-lxde" "$out/xinitrc-lxde"
install -m 0644 "$repo_root/configs/variants/gtkrc-2.0" "$out/lxde/gtkrc-2.0"
install -m 0644 "$repo_root/configs/variants/gtk-3.0/settings.ini" "$out/lxde/settings.ini"
cp -a "$repo_root/configs/variants/applications/." "$out/lxde/applications/"

install -d "$out/bin"
install -m 0755 "$repo_root/configs/variants/bin/pico-8" "$out/bin/pico-8"

# PICO-8 CHIP build.
fetch "$pico8_url" "$work/pico-8.zip"
[[ -s "$work/pico-8.zip" ]] || die "empty PICO-8 download: $pico8_url"
unzip -q -o "$work/pico-8.zip" -d "$work/pico-8-unpacked"
[[ -f "$work/pico-8-unpacked/pico-8/pico8" ]] ||
  die "PICO-8 archive layout changed: $pico8_url"
chmod 0755 "$work/pico-8-unpacked/pico-8/pico8"
install -d "$out/pico-8"
cp -a "$work/pico-8-unpacked/pico-8/." "$out/pico-8/"

# SunVox. The lofi armhf build is the one that runs on a Cortex-A8.
fetch "$sunvox_url" "$work/sunvox.zip"
[[ -s "$work/sunvox.zip" ]] || die "empty SunVox download: $sunvox_url"
unzip -q -o "$work/sunvox.zip" -d "$work/sunvox-unpacked"
sunvox_bin="$(find "$work/sunvox-unpacked" -type f -name 'sunvox_lofi' | head -1)"
[[ -n "$sunvox_bin" ]] || die "sunvox_lofi not found in $sunvox_url"
install -d "$out/sunvox"
install -m 0755 "$sunvox_bin" "$out/sunvox/sunvox_lofi"

# Battery daemon sources; built inside the chroot so the image keeps its own
# compiler ABI.
clone_repo "$batt_repo" "$work/pocketchip-batt" "$batt_ref"
install -d "$out/batt"
# pocketchip-one.c predates modern libc headers and relies on transitive
# includes; GCC 14 treats the resulting implicit declarations as errors.
{
  printf '%s\n' \
    '#include <unistd.h>' \
    '#include <sys/ioctl.h>' \
    '#include <sys/stat.h>' \
    '#include <stdlib.h>' \
    '#include <string.h>'
  cat "$work/pocketchip-batt/pocketchip-one.c"
} > "$out/batt/pocketchip-one.c"
cp -a "$work/pocketchip-batt/pocketchip-one.service" "$out/batt/"

printf 'prepared %s extras in %s\n' "$variant" "$out"
