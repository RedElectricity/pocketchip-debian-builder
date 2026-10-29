# PocketCHIP NAND Path

This is the experimental direct-NAND path for the Debian 13 PocketCHIP image.
Keep UART connected and keep FEL recovery working before using it. The flash
step erases the internal NAND.

## Current Strategy

Use the legacy CHIP-tools NAND layout for boot assets:

- SPL at `0x00000000`
- backup SPL at `0x00400000`
- U-Boot at `0x00800000`
- environment at `0x00c00000`
- raw boot payload area at `0x01000000` through `0x04ffffff`
- UBI root filesystem from `0x05000000`

The Debian kernel has `sunxi_nand`, `ubi`, `ubifs`, and `ofpart` as modules, so
the NAND image installs a NAND-enabled DTB and rebuilds the initramfs with those
modules forced in. The fixed DT partitions mirror the legacy CHIP layout because
the Debian kernel does not currently have `CONFIG_MTD_CMDLINE_PARTS` enabled.

Mainline NAND U-Boot remains a probe/compare path until it proves it can detect
the PocketCHIP NAND reliably and boot back from NAND. The first destructive path
should use the production MLC PocketCHIP legacy branch in
`build/u-boot-legacy-mlc-pc`; the older `chip/stable` build has been observed to
report `NAND: 0 MiB` on this device.

Important current result: the PocketCHIP tested here has 4 GiB Toshiba MLC NAND
(`400000-4000-500`). The basic flash flow succeeds, and legacy U-Boot can attach
the UBI image and read `/boot` from UBIFS. Debian 13's mainline-style kernel
then refuses to attach plain UBI on MLC NAND:

```text
ubi: refuse attaching mtd4 - MLC NAND is not supported
```

The preferred persistent NAND path is now SLC-on-MLC emulation, not a patched
Debian `ubi.ko` that blindly bypasses this guard. Linux accepts UBI on an MLC
partition when the MTD partition is exposed with the `slc-mode` fixed-partition
flag. The SLC path therefore:

- builds a patched legacy PocketCHIP U-Boot in an isolated worktree;
- restores the old CHIP SLC-mode NAND write/read helpers and fastboot `UBI`
  SLC write behavior;
- generates a NAND DTB with `slc-mode;` on the `UBI` partition;
- writes U-Boot, `zImage`, the NAND DTB, and `initrd.uimage` with U-Boot's
  `.slc-mode` NAND helpers. SPL applies the matching Toshiba lower-page mapping
  when loading the U-Boot slot, and old U-Boot never needs to mount the
  slc-mode UBI volume;
- builds the rootfs UBIFS image as 2 MiB logical SLC eraseblocks with
  an autoresizing rootfs volume using LZO UBIFS compression. The preferred
  rootfs write path is now the Linux rescue installer, which formats UBI and
  writes the UBIFS volume through the same `sunxi_nand`/UBI stack that will
  mount it at runtime.
  Autoresize is intentional: Linux UBI needs to reserve wear-leveling and
  bad-block handling PEBs before expanding the persistent volume.

This trades capacity for reliability. The 4 GiB physical MLC NAND is treated as
roughly 2 GiB of logical SLC-mode NAND for Linux. Clean shutdowns still matter;
this is raw NAND, not eMMC.

## Host Preflight

```sh
./scripts/nand-preflight.sh
```

If tools are missing:

```sh
sudo apt install mtd-utils android-sdk-libsparse-utils fastboot u-boot-tools
sudo apt install gcc-arm-linux-gnueabi
./scripts/build-sunxi-tools-misc.sh
./scripts/build-chip-mtd-utils.sh
```

`gcc-arm-linux-gnueabi` is needed for the legacy CHIP U-Boot build. The normal
USB/FEL mainline U-Boot build uses `gcc-arm-linux-gnueabihf`.

The MLC NAND images require the old CHIP `ubinize -M dist3` page-pairing
extension. Debian's packaged `ubinize` does not include that option, so
`build-chip-mtd-utils.sh` installs the patched binary into
`build/host-tools/bin`.

## Build Artifacts

```sh
./scripts/fetch-upstreams.sh
make uboot-legacy-mlc-pc-slc
make nand-image-mlc-pc-slc
```

Expected output directory:

```text
build/nand/images/
  sunxi-spl.bin
  u-boot-dtb.bin
  u-boot-nand.img
  spl-<erase>-<page>-<oob>.bin
  uboot-<erase>.bin
  boot-zImage-<erase>-<page>-<oob>.bin
  boot-sun5i-r8-chip-<erase>-<page>-<oob>.dtb
  boot-initrd-<erase>-<page>-<oob>.uimage
  boot-layout-<erase>-<page>-<oob>.env
  chip-<erase>-<page>-<oob>.ubi.sparse
```

The SLC-mode build uses a separate output directory so it is not confused with
the older plain-MLC proof image:

```text
build/nand-slc/images/
  nand_slc_mode
  sunxi-spl.bin
  u-boot-dtb.bin
  u-boot-nand.img
  spl-400000-4000-500.bin
  uboot-400000.bin
  boot-zImage-400000-4000-500.bin
  boot-sun5i-r8-chip-400000-4000-500.dtb
  boot-initrd-400000-4000-500.uimage
  boot-layout-400000-4000-500.env
  chip-400000-4000-500.ubi.sparse
```

`u-boot-dtb.bin` is kept for FEL execution from DRAM. `uboot-<erase>.bin` is
the NAND second-stage image; prefer the mkimage-wrapped `u-boot-dtb.img` source
so SPL reads the actual U-Boot length instead of a fixed raw 768 KiB window.

The builder knows these NAND geometries:

```text
hynix-8g-mlc       400000-4000-680
toshiba-4g-mlc     400000-4000-500
toshiba-512m-slc   40000-1000-100
```

The `uboot-legacy-mlc-pc-slc` build applies a Toshiba-specific SPL patch for
the current PocketCHIP target. That SPL uses the known Toshiba 4G MLC boot
geometry directly: 16 KiB pages, 1 KiB ECC steps, ECC40, 5 address cycles, and
NAND randomization. It also applies Toshiba SLC lower-page mapping when reading
the U-Boot slot, matching the `.slc-mode` write path and avoiding fragile normal
MLC reads for second-stage U-Boot. Full U-Boot remains generic; only the tiny
NAND SPL skips the fragile geometry auto-detection path. Add a separate SPL
geometry/page-mapping patch before using the same boot image flow on Hynix MLC
units.

The legacy SLC build also enables the default PocketCHIP Cortex-A8 Spectre v2
mitigation path. `POCKETCHIP_SPECTRE_V2_MITIGATION=1` adds an early U-Boot
ACTLR IBE-bit write so Linux branch predictor hardening is active instead of
printing the boot-time firmware warning. Set it to `0` only for controlled
benchmark comparisons.

By default `build-nand-image.sh` creates UBIFS with `NAND_UBIFS_COMPRESSOR=lzo`.
The builder also forces the kernel's `zstd` crypto module into the initramfs
when the module is present, because an older flashed UBIFS volume or compressor
metadata can otherwise stop boot at initramfs with `cannot initialize compressor
zstd`.

The current Debian rootfs is too large for the 512 MiB SLC target, so that
format should be skipped unless the image is reduced substantially.

## Probe NAND Geometry

Put the PocketCHIP in FEL mode with UART attached, then run the serial probe
using the production MLC PocketCHIP U-Boot:

```sh
sudo ./scripts/fel-nand.py probe-legacy-serial --uboot-dir build/u-boot-legacy-mlc-pc
```

This is read-only. It loads NAND-capable U-Boot through FEL, runs `nand info`,
and writes the detected geometry from UART output. The non-serial probe also
exports the geometry to SRAM and resets back into FEL, but this board can land
in a stale FEL state where `lsusb` shows `1f3a:efe8` while `sunxi-fel ver` times
out. If that happens, clear the host-side USB device with `sudo usbreset
1f3a:efe8` and physically re-enter FEL.

Successful probes write:

```text
build/nand/legacy-serial-probe.env
build/nand/images/ubi_type
```

The older SRAM-export probe is still available as a fallback:

```sh
sudo ./scripts/fel-nand.py probe-legacy
```

Optional mainline comparison:

```sh
./scripts/build-mainline-nand-uboot.sh
sudo ./scripts/fel-nand.py probe-mainline
```

Only use the mainline NAND U-Boot for flashing after it detects NAND correctly
and has been tested through a full boot cycle.

## Flash NAND

After the probe and image build both match the detected `ubi_type`:

```sh
CONFIRM_NAND_WRITE=YES make nand-flash-chip-tools-slc
```

That stages the official CHIP-tools at a pinned commit with
`tools/chip-tools-pocketchip.patch` applied, then runs
`chip-update-firmware.sh -p -r -L build/nand-slc/images -F Toshiba_4G_MLC`.
The patch replaces CHIP-tools' `flash_images` for SLC-mode images: the stock
version asks U-Boot to mount `ubi0:rootfs`, but U-Boot cannot attach a
slc-mode UBI volume, so the patched function writes the kernel, DTB and initrd
to their raw NAND slots with `.slc-mode` helpers and leaves the UBI partition
to fastboot. It also drops the `-i 0x1f3a`/`-u` fastboot options that current
host tools reject, and accepts absolute `-L` paths.

The first flash of a board whose saved environment was written by an older
`fel-nand.py` still needs one serial-triggered run, because that environment
does not contain the `fel_booted`/`scriptaddr` guard that lets a FEL-loaded
U-Boot script run by itself. Use `make nand-flash-legacy-slc` once for that
migration; it now saves an environment with the guard, so later CHIP-tools
flashes need no UART input.

The older plain-MLC proof image can still be flashed with `make
nand-flash-legacy`, but it is expected to hit the Debian `MLC NAND is not
supported` UBI guard unless a custom kernel/module override is added.

The flash flow:

1. FEL-loads SPL, U-Boot, and a generated U-Boot script into DRAM.
2. Erases NAND with `nand erase.chip`.
3. Writes primary SPL, backup SPL, and U-Boot.
4. Writes raw NAND boot assets with `.slc-mode`:
   `zImage` at `0x01000000`, DTB at `0x02000000`, and `initrd.uimage` at
   `0x02400000`.
5. Saves a raw-NAND boot environment with `ubi.mtd=UBI`, not a numeric MTD
   index. U-Boot loads the boot assets with `nand read.slc-mode`; Linux mounts
   UBIFS after the kernel starts.
6. Enters U-Boot fastboot.
7. Flashes the sparse UBI image to the `UBI` partition. Both flash paths refuse
   unless the image directory is marked with `nand_slc_mode=1`.

Step 7 is not reliable enough to be the rootfs install path. U-Boot writes and
verifies the sparse image itself, but Linux can still find an uncorrectable
BCH page afterwards: the observed failures were single data pages near the end
of the UBI image (PEB 509 in one flash, PEB 466 in another). UBI then attaches
and UBIFS mounts, but reading a directory entry fails and the graphical session
never starts, which looks like a black screen after the splash. U-Boot cannot
detect this, because it verifies with its own read path.

Per-block repair through U-Boot is not a durable fix either. On the tested unit
a block written with `nand write.slc-mode` and then read back with
`nand read.slc-mode` plus `cmp.b` still failed the kernel's ECC read path in the
same boot session (`error -74 ... read 0 bytes`), so U-Boot's read-retry
handling is more forgiving than `sunxi_nand` for marginal MLC pages. Rewriting
such pages only moves the failure to a neighbouring page. Let Linux own the
whole UBI write instead.

Use CHIP-tools only for the boot area, and let Linux own the rootfs:

```sh
CONFIRM_NAND_WRITE=YES make nand-flash-chip-tools-assets-slc
```

`POCKETCHIP_SKIP_UBI=1` makes the patched CHIP-tools erase and write SPL,
U-Boot, `zImage`, DTB and initrd, then leave U-Boot fastboot without touching
the UBI partition.

If a freshly rewritten UBIFS rootfs repeatedly reports an uncorrectable UBI
read from the same PEB, mark that single eraseblock bad before reflashing. For
example, UBI `PEB 423` maps to absolute NAND offset `0x6ec00000` with this
layout (`0x05000000 + 423 * 0x400000`):

```sh
sudo ./scripts/fel-nand.py \
  --nand-dir build/nand-slc \
  --images-dir build/nand-slc/images \
  --timeout 240 \
  flash-legacy \
  --format toshiba-4g-mlc \
  --require-slc-mode \
  --source-over-serial \
  --markbad-offset 0x6ec00000 \
  --i-understand-this-erases-nand
```

Use `--erase-mode scrub` only if targeted bad-block marking plus normal erase is
not enough; scrub is more aggressive around bad-block metadata.

## Linux-Side UBI Rescue Install

This is the recommended way to install the persistent rootfs. It FEL-boots the
Debian kernel with a small initramfs, formats the `UBI` MTD partition with
Linux `ubiformat`, creates the `rootfs` UBI volume, and writes the UBIFS
payload with Linux `ubiupdatevol`. Linux handles bad blocks and ECC during the
write, so the volume is readable by the same stack that mounts it at boot.

The `nand-pocketchip` CI artifact now contains the rescue initrd
(`nand-rescue-initrd-400000-4000-500.uimage`) next to the boot assets. Point the
host targets at the downloaded artifact if you did not build locally:

```sh
NAND_DIR=build/artifacts/40806243433/nand-pocketchip \
  CONFIRM_NAND_WRITE=YES make nand-rescue-install-usb-slc
```

The rescue initrd expects a UBIFS payload rather than the UBI image. Extract it
from the sparse UBI artifact; the helper expands the sparse file and follows
the UBI VID headers, so no Linux host is needed:

```sh
make nand-ubi-payload-slc NAND_DIR=build/artifacts/40806243433/nand-pocketchip
```

Put the result on a FAT32 or ext4 stick:

```sh
make nand-rescue-usb-payload-slc \
  NAND_DIR=build/artifacts/40806243433/nand-pocketchip \
  USB_MOUNT=/Volumes/POCKETCHIP
```

The helper writes `pocketchip/rootfs.ubifs` plus a `.sha256` file to the mounted
stick. Plug that stick into the PocketCHIP USB host port, boot the board into
FEL, then run:

```sh
NAND_DIR=build/artifacts/40806243433/nand-pocketchip \
  CONFIRM_NAND_WRITE=YES make nand-rescue-install-usb-slc
```

The rescue initramfs waits for the USB storage device, mounts it read-only,
verifies the payload size and SHA256 against the build artifact, writes
`/dev/ubi0_0`, syncs, and reboots.

### Wi-Fi payload

When no USB storage is available, build the rescue initramfs with the Wi-Fi
source (`rescue_source=wifi` in the CI workflow, or
`make nand-rescue-initramfs-wifi-slc`) and stream the payload over the local
network:

```sh
NAND_DIR=build/artifacts/40863894173/nand-pocketchip \
  NAND_RESCUE_WIFI_SSID='my-ssid' NAND_RESCUE_WIFI_PSK='my-passphrase' \
  CONFIRM_NAND_WRITE=YES make nand-rescue-install-wifi-slc
```

The initramfs loads the staging `r8723bs` driver, scans 2.4 GHz networks, prints the visible
SSIDs, prompts for SSID and password on the serial console, associates with
`wpa_supplicant`, obtains a DHCP lease, and waits for a TCP stream on port
`4242`. The host streams the extracted UBIFS directly into `ubiupdatevol`; the
initramfs then hashes the written volume and compares it with the baked SHA256
before rebooting. Credentials are passed through the environment and are never
stored in the repository, and password echo is disabled so the passphrase does
not land in the serial log. The PocketCHIP radio is 2.4 GHz only.

A USB-gadget network rescue still exists (`NAND_RESCUE_SOURCE=net` and
`make nand-rescue-install-slc`) with host/device addresses `172.16.42.1` and
`172.16.42.2` on TCP port `4242`. On this PocketCHIP, Debian's MUSB gadget path
exposes `/sys/class/udc/musb-hdrc.1.auto` but `g_ether` fails to start the
controller, so prefer the Wi-Fi or USB-stick payload.

If the rootfs UBI partition was already written and only the boot area needs a
refresh, use the bootloader target from FEL mode:

```sh
CONFIRM_NAND_WRITE=YES make nand-flash-bootloader-slc
```

That path erases and rewrites only the first 80 MiB NAND boot area:
`spl`, `spl-backup`, `uboot`, `env`, and the raw `boot` payloads. It
intentionally leaves the `UBI` partition at `0x05000000` untouched.

## Verify NAND Boot

After flashing, power-cycle without the USB rootfs drive. Keep UART connected:

```sh
sudo ./scripts/fel-nand.py verify --root-password '<lab-root-password>'
```

The verifier checks the serial shell for Debian, `/proc/cmdline`, `/proc/mtd`,
UBIFS mounts, NAND/UBI modules, and i3 process state.
New default images lock root, so use the serial login for the configured user
or build a temporary lab image with `POCKETCHIP_ROOT_AUTH=password` only when
this root verifier path is needed.

For a persistence smoke test:

```sh
echo nand-persist-test-$(date +%s) >"$HOME/nand-persist-test.txt"
sync
reboot
cat "$HOME/nand-persist-test.txt"
```

## Recovery Notes

- FEL mode remains the recovery path if NAND boot fails.
- USB/FEL boot remains the safest way to test rootfs, display, keyboard, Wi-Fi,
  Bluetooth, and i3 changes.
- Direct Linux-side NAND writes are not the preferred first path. The current
  USB boot does not expose `/proc/mtd` until a NAND-enabled DTB and initramfs are
  used, and raw NAND writes from Linux add more risk than the U-Boot fastboot
  flow.
