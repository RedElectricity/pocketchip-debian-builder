# Image Variants

This fork adds two prebuilt image flavours on top of the upstream builder. Both share the same Debian 13/trixie `armhf` rootfs, mainline U-Boot, FEL/USB boot path, Wi-Fi, Bluetooth, SSH, and the PocketCHIP power/lock helpers. They differ only in the desktop session and the device-tree overlay.

| | PocketCHIP | Desktop CHIP |
| --- | --- | --- |
| Display | PocketCHIP LCD (pocketchip-v73 overlay) | CHIP HDMI adapter (dip-hdmi overlay) |
| Session | `awesome` + [pocketchip-menu](https://github.com/omgmog/pocketchip-menu) as the home screen | XFCE |
| Fallback | `i3` still installed | none |
| Extras | PICO-8 0.2.4, SunVox 2.1.4d (lofi), pocketchip-batt binary | PICO-8/SunVox not installed |
| Keyboard | PocketCHIP matrix keymap and Fn layers | USB keyboard, default keymap |

The image is a USB root filesystem: write it to a USB drive, put the drive in the CHIP USB host port, then boot the board through FEL with the matching U-Boot binary. Nothing is written to NAND.

Both variants install the kernel from the base suite (trixie's 6.12 LTS). The 7.x kernel from `trixie-backports` is not usable here: its rewritten sunxi NAND driver misreads the SLC-mode UBI volume and boot hangs on a UBIFS ECC error, so the backports kernel stays opt-in. Set `KERNEL_SUITE` in the environment, or the `POCKETCHIP_KERNEL_SUITE` repository variable in Actions, to another suite such as `sid`; `none` explicitly selects the base suite's kernel. The base package set already includes `openssh-server` (enabled at boot), `openssh-client`, NetworkManager, `git`, `tmux`, `neovim`/`vim`, `curl`/`wget`, `htop`, `rsync`, `zstd`, `zip`/`unzip`, and the usual diagnostics.

## Building in GitHub Actions

`.github/workflows/build.yml` builds both variants in parallel on `ubuntu-24.04` runners. Run it from **Actions → build images → Run workflow**; pick `both`, `pocketchip`, or `desktop`. Pushing a `v*` tag also builds both images and attaches them to the GitHub release.

Each job produces two artifacts:

- `image-<variant>`: `build/images/<variant>-debian-trixie-armhf.img.zst` and its `.sha256`.
- `boot-<variant>`: `u-boot-sunxi-with-spl.bin` plus the built DTBs/DTBOs.

The workflow installs `qemu-user-static` and registers `qemu-arm` binfmt so the armhf chroot can run package maintainer scripts on the x86 runner. Upstream checkouts (U-Boot, CHIP-linux, CHIP-dt-overlays, ...) are cached between runs. Repository variable `POCKETCHIP_TIMEZONE` overrides the default `Asia/Shanghai`, and `POCKETCHIP_KERNEL_SUITE` overrides the default `none` kernel suite selection (the base suite's kernel).

## Building locally

The build host must be Linux; the scripts use loop devices, `chroot`, GNU `find -printf`, and qemu binfmt. On Debian/Ubuntu install the dependency list from the main README, then:

```sh
./scripts/check-host.sh
./scripts/fetch-upstreams.sh

# PocketCHIP variant
./scripts/build-mainline-uboot.sh
./scripts/build-pocketchip-dtbo.sh
./scripts/variants/prepare-extras.sh pocketchip
sudo env \
  POCKETCHIP_EXTRA_PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' configs/variants/pocketchip.packages | tr '\n' ' ')" \
  POCKETCHIP_EXTRAS_DIR="$PWD/build/extras" \
  POCKETCHIP_POST_INSTALL="$PWD/scripts/variants/pocketchip-post-install.sh" \
  ./scripts/build-rootfs.sh
sudo env SIZE_MB=4096 \
  DTBO="$PWD/build/dtbo/pocketchip-v73-mainline.dtbo" \
  MERGED_DTB="$PWD/build/dtbo/sun5i-r8-pocketchip.dtb" \
  DTB_NAME=sun5i-r8-pocketchip.dtb \
  ./scripts/build-usb-image.sh
```

For the Desktop CHIP variant, replace the DT steps with the HDMI overlay and use the desktop package list and post-install script:

```sh
SOURCE_DTSO="$PWD/dts/chip-hdmi.dts" \
OUT_DTBO="$PWD/build/dtbo/dip-hdmi.dtbo" \
OUT_DTB="$PWD/build/dtbo/sun5i-r8-chip-hdmi.dtb" \
  ./scripts/build-pocketchip-dtbo.sh

./scripts/variants/prepare-extras.sh desktop
sudo env \
  POCKETCHIP_EXTRA_PACKAGES="$(grep -vE '^[[:space:]]*(#|$)' configs/variants/desktop.packages | tr '\n' ' ')" \
  POCKETCHIP_EXTRAS_DIR="$PWD/build/extras" \
  POCKETCHIP_POST_INSTALL="$PWD/scripts/variants/desktop-post-install.sh" \
  ./scripts/build-rootfs.sh
sudo env SIZE_MB=4096 \
  MERGED_DTB="$PWD/build/dtbo/sun5i-r8-chip-hdmi.dtb" \
  DTB_NAME=sun5i-r8-chip-hdmi.dtb \
  ./scripts/build-usb-image.sh
```

## Flashing

1. Write the image to a USB drive (the CHIP boots the rootfs from it):

   ```sh
   zstd -d --stdout pocketchip-debian-trixie-armhf.img.zst | \
     sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
   ```

2. Put the drive in the CHIP USB host port and connect the micro-USB data port to the build host.

3. Ground the `FEL` pad, power-cycle the board, and confirm the host sees `1f3a:efe8` (`sunxi-fel ver`). See `docs/fel-mode.md`.

4. Load U-Boot:

   ```sh
   sudo sunxi-fel uboot u-boot-sunxi-with-spl.bin
   ```

U-Boot then boots the kernel and initrd from the USB rootfs. Keep a 3.3 V UART adapter attached for the first boot.

On macOS there is no Homebrew `sunxi-tools` formula. Docker Desktop cannot pass USB devices into a container, so a container is not a shortcut for this step either.

### macOS FEL toolchain

`sunxi-fel` needs both libusb and libfdt. With Homebrew's `libusb` present, build a static libfdt from dtc and link it statically:

```sh
mkdir -p ~/.local/src ~/.local/bin

git clone --depth 1 https://git.kernel.org/pub/scm/utils/dtc/dtc.git ~/.local/src/dtc
make -C ~/.local/src/dtc NO_PYTHON=1 NO_YAML=1 WARNINGS= libfdt/libfdt.a

git clone --depth 1 https://github.com/linux-sunxi/sunxi-tools.git ~/.local/src/sunxi-tools
make -C ~/.local/src/sunxi-tools sunxi-fel \
  LIBFDT_CFLAGS="-I$HOME/.local/src/dtc/libfdt" \
  LIBFDT_LIBS="$HOME/.local/src/dtc/libfdt/libfdt.a"
install -m 0755 ~/.local/src/sunxi-tools/sunxi-fel ~/.local/bin/
```

Make sure `~/.local/bin` is on `PATH`, then verify with `sunxi-fel` (it prints usage without a device). `sunxi-fel version` only works once a device is in FEL mode.

## Variant notes

### PocketCHIP

- `~/.xinitrc` starts `awesome`; `~/.config/awesome/rc.lua` launches `pocketchip-menu/load.sh` fullscreen and keeps its window on top.
- `Mod1+h` (Alt+H) relaunches the home screen if it is closed. `Mod1+Tab` and `Ctrl+Tab` cycle windows, `Mod1+Return` opens `dmenu_run`, `Ctrl+Q` closes the focused window (never the menu).
- The upstream `i3` session is still installed. To go back to it, edit `~/.xinitrc` and replace `awesome` with `i3`.
- `pocketchip-batt` is compiled into the image and its unit is installed, but it is **not enabled**: on a mainline kernel `upower` already reports the AXP209 battery through the kernel driver, and the daemon writes to the same I2C device. Enable it manually with `sudo systemctl enable --now pocketchip-one` if you need the legacy `/usr/lib/pocketchip-batt` files.
- PICO-8 and SunVox are proprietary binaries downloaded from their upstream URLs at build time. They are not redistributed by this repository.

### Desktop CHIP

- `~/.xinitrc` starts `startxfce4`.
- The PocketCHIP console keymap service is masked, because it would remap a USB keyboard with the matrix-keyboard layout.
- The PocketCHIP touch calibration Xorg snippet is removed.
- Debian's `linux-image-armmp` does **not** enable `CONFIG_DRM_I2C_CH7033`, the driver for the CHIP HDMI adapter bridge, and it also leaves the dumb VGA bridge driver off. The image therefore builds the upstream `chrontel-ch7033.c` as an out-of-tree module against the installed `linux-headers-armmp` and loads it through `/etc/modules-load.d/ch7033.conf`. This path is untested on hardware; verify it with a UART console before relying on HDMI.
- `dts/chip-hdmi.dts` is a local copy of the upstream overlay with two fixes for mainline: the pinmux label is `i2c1_pins` (upstream still says `i2c1_pins_a`) and the alias points at `/soc/i2c@1c2b000`. The upstream overlay fails to apply with `FDT_ERR_NOTFOUND` on current U-Boot/kernel device trees.
- The CH7033 HDMI bridge does not always provide usable EDID. If the panel comes up at the wrong size, set the mode once from an XFCE terminal:

  ```sh
  xrandr --output HDMI-1 --mode 1280x720
  ```
