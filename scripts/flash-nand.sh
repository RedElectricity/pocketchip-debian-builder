#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Flash the SLC-mode NAND image with the official CHIP-tools flow. The
# PocketCHIP patch in tools/chip-tools-pocketchip.patch teaches chip-tools to
# write the raw boot assets with U-Boot's .slc-mode helpers instead of asking
# U-Boot to mount the UBI volume, which it cannot do for SLC-mode NAND.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
images_dir="${1:-$repo_root/build/nand-slc/images}"
chip_tools_dir="${CHIP_TOOLS_DIR:-$repo_root/build/CHIP-tools}"
format="${POCKETCHIP_NAND_FORMAT:-Toshiba_4G_MLC}"

case "$format" in
  Toshiba_4G_MLC) suffix="400000-4000-500" ;;
  Hynix_8G_MLC) suffix="400000-4000-680" ;;
  Toshiba_512M_SLC) suffix="40000-1000-100" ;;
  *)
    printf 'error: unknown POCKETCHIP_NAND_FORMAT=%s\n' "$format" >&2
    exit 2
    ;;
esac

if [[ ! -d "$images_dir" ]]; then
  printf 'error: %s does not exist; build it with make nand-image-mlc-pc-slc\n' "$images_dir" >&2
  exit 2
fi
images_dir="$(cd "$images_dir" && pwd)"

if [[ "${CONFIRM_NAND_WRITE:-}" != "YES" ]]; then
  printf 'Refusing NAND write. Re-run with CONFIRM_NAND_WRITE=YES.\n' >&2
  exit 2
fi

if [[ "$(cat "$images_dir/nand_slc_mode" 2>/dev/null || true)" != "1" ]]; then
  printf 'error: %s is not marked as an SLC-mode NAND image\n' "$images_dir" >&2
  printf '       rebuild with make nand-image-mlc-pc-slc\n' >&2
  exit 2
fi

required=(
  sunxi-spl.bin
  u-boot-dtb.bin
  "spl-$suffix.bin"
  "uboot-${suffix%%-*}.bin"
  "boot-zImage-$suffix.bin"
  "boot-sun5i-r8-chip-$suffix.dtb"
  "boot-initrd-$suffix.uimage"
  "chip-$suffix.ubi.sparse"
)
missing=0
for name in "${required[@]}"; do
  if [[ ! -f "$images_dir/$name" ]]; then
    printf 'error: missing %s\n' "$images_dir/$name" >&2
    missing=1
  fi
done
if ((missing)); then
  exit 2
fi

if [[ ! -x "$chip_tools_dir/chip-update-firmware.sh" ]]; then
  printf 'error: CHIP-tools is not staged; run %s/scripts/fetch-chip-tools.sh\n' "$repo_root" >&2
  exit 2
fi
if ! grep -q 'pocketchip_flash_images' "$chip_tools_dir/common.sh"; then
  printf 'error: CHIP-tools is missing the PocketCHIP SLC patch; rerun scripts/fetch-chip-tools.sh\n' >&2
  exit 2
fi

for tool in sunxi-fel fastboot mkimage; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: %s is not installed or not on PATH\n' "$tool" >&2
    exit 2
  fi
done

printf 'Flashing %s (%s) with CHIP-tools from %s\n' "$images_dir" "$format" "$chip_tools_dir"
printf 'This erases the CHIP NAND.\n'

# CHECK_DEPS skips CHIP-tools' own dependency probe, which also demands
# sunxi-nand-image-builder even though this flow never uses it.
cd "$chip_tools_dir"
exec env CHECK_DEPS=1 POCKETCHIP_SLC=1 \
  ./chip-update-firmware.sh -p -r -L "$images_dir" -F "$format"
