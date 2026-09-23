#!/bin/bash
# systemLinux v1!!!! ISO build: a normal live ISO (small initramfs + /live/rootfs.squashfs, mounted
# with an overlayfs; nothing is loaded into a RAM disk), with systemd as init, goget, boot/disk
# tools, the full-driver kernel and firmware. Console/minimal only — there is no desktop edition.
#
#   ./build_iso.sh    -> systemlinux-v1.2.iso  (root shell, console only, installable with the handbook)
#
# Run from a normal terminal (sudo needs a password prompt). Works from any Linux host with
# grub2, xorriso, mtools, squashfs-tools and cpio on PATH (install them with your host's own
# package manager, e.g. `emerge sys-boot/grub app-cdr/xorriso sys-fs/mtools sys-fs/squashfs-tools
# app-arch/cpio` on Gentoo, `apt install grub2 xorriso mtools squashfs-tools cpio` on Debian, or
# equivalent). GRUB/efibootmgr/dosfstools/fastfetch for the *target* image are fetched from
# nixpkgs by goget itself (built below) — no host package manager involvement there, and no
# Debian dependency anywhere in this pipeline. UEFI only: nixpkgs' grub build has no i386-pc
# (legacy BIOS) modules, matching this project's own "UEFI only, BIOS untested" stance.
set -euo pipefail

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOTFS=$BUILD_DIR/rootfs
WORKSPACE=$BUILD_DIR/iso_workspace
# the "full" kernel is the same Linux 7.2.6 with drivers for almost everything built in
KERNEL=${KERNEL:-$BUILD_DIR/tools/kernel-full/vmlinuz-7.2.6-full}
IMAGE_VERSION=$(cat "$BUILD_DIR/VERSION")
ISO=${ISO:-$BUILD_DIR/systemlinux-v$IMAGE_VERSION.iso}
FW_WORK=${FW_WORK:-$HOME/.cache/systemlinux-firmware}
BASE_WORK=${BASE_WORK:-$HOME/.cache/systemlinux-base}
BOOT_WORK=${BOOT_WORK:-$HOME/.cache/systemlinux-boot}
cd "$BUILD_DIR"
# fail early, with the fix, instead of halfway through the kernel build
missing=
for t in xorriso mksquashfs mformat cpio python3 go make gcc flex bison bc perl pahole; do
    command -v "$t" >/dev/null || missing="$missing $t"
done
command -v grub-mkrescue >/dev/null || command -v grub2-mkrescue >/dev/null || missing="$missing grub-mkrescue"
if [ -n "$missing" ]; then
    echo "ERROR: missing build tools:$missing"
    echo "  Fedora: sudo dnf install xorriso squashfs-tools mtools cpio golang flex bison bc dwarves elfutils-libelf-devel openssl-devel openssl-devel-engine grub2-tools-extra"
    echo "  Debian: sudo apt install xorriso squashfs-tools mtools cpio golang flex bison bc dwarves libelf-dev libssl-dev grub-common"
    exit 1
fi
# Fedora and friends name the GRUB tools grub2-*
GRUB_MKRESCUE=$(command -v grub-mkrescue || command -v grub2-mkrescue || echo grub-mkrescue)
GRUB_SCRIPT_CHECK=$(command -v grub-script-check || command -v grub2-script-check || echo grub-script-check)

echo "=== [1/8] COMPILING goget AND THE FULL KERNEL ==="
if [ ! -f "$KERNEL" ]; then "$BUILD_DIR/tools/kernel-full/build-kernel.sh"; fi
[ -f "$KERNEL" ] || { echo "ERROR: kernel not found at $KERNEL"; exit 1; }
make -C ./goget
GOGET=$BUILD_DIR/goget/goget

echo "=== [2/8] INSTALLING goget AND init LINKS INTO ROOTFS ==="
# /sbin is a symlink to usr/bin in this rootfs, so this lands in usr/bin
sudo install -Dm755 ./goget/goget "$ROOTFS/usr/bin/goget"
sudo install -Dm755 ./goget/goget "$ROOTFS/usr/local/bin/goget"
sudo rm -f "$ROOTFS/init" "$ROOTFS/sbin/init" "$ROOTFS/sbin/lenine"
sudo ln -sf usr/lib/systemd/systemd "$ROOTFS/init"
sudo ln -sf ../lib/systemd/systemd "$ROOTFS/sbin/init"
for n in reboot poweroff halt shutdown; do
    sudo ln -sf systemctl "$ROOTFS/usr/bin/$n"
done
# boot to the console (there is no display manager), with NetworkManager and a tmpfs /tmp
sudo ln -sf /usr/lib/systemd/system/multi-user.target "$ROOTFS/etc/systemd/system/default.target"
sudo mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants" "$ROOTFS/etc/systemd/system/local-fs.target.wants"
sudo ln -sf /usr/lib/systemd/system/NetworkManager.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
sudo ln -sf /usr/lib/systemd/system/tmp.mount "$ROOTFS/etc/systemd/system/local-fs.target.wants/tmp.mount"
sudo install -Dm644 "$KERNEL" "$ROOTFS/boot/vmlinuz"

echo "=== [3/8] ROOTFS FIXES AND BRANDING ==="
# D-Bus activation needs the launch helper setuid root (it was owned by the build user with no setuid bit)
# (the image's own messagebus gid: the host may not have that group, e.g. Fedora calls it dbus)
MB=$(sed -n 's/^messagebus:[^:]*:\([0-9]*\):.*/\1/p' "$ROOTFS/etc/group")
sudo chown "0:${MB:?no messagebus group in $ROOTFS/etc/group}" "$ROOTFS/usr/libexec/dbus-daemon-launch-helper"
sudo chmod 4750 "$ROOTFS/usr/libexec/dbus-daemon-launch-helper"
# GNU bash is the system shell (/bin/bash and /bin/sh); the bbash fork stays installed as its own command.
# Built static, so it does not depend on the base's libtinfo. The libarchive tools (BSD tar and friends)
# are removed: GNU tar is the tar.
[ -x tools/gnu-bash/bash ] || tools/gnu-bash/build.sh
sudo install -Dm755 tools/gnu-bash/bash "$ROOTFS/usr/bin/bash"
sudo ln -sf bash "$ROOTFS/usr/bin/sh"
sudo rm -f "$ROOTFS"/usr/bin/bsdtar "$ROOTFS"/usr/bin/bsdcat "$ROOTFS"/usr/bin/bsdcpio "$ROOTFS"/usr/bin/bsdunzip
# issue, os-release, release files and the login banner (GNU/Linux branding)
sudo ./goget/goget provision "$ROOTFS"
# fastfetch: the cat logo as ASCII art (assets/fastfetch/make-logo.py regenerates it from assets/logo.png),
# for root and, through /etc/skel, for every new user
sudo install -Dm644 assets/fastfetch/logo.txt "$ROOTFS/usr/share/systemlinux/fastfetch-logo.txt"
sudo install -Dm644 assets/fastfetch/config.jsonc "$ROOTFS/root/.config/fastfetch/config.jsonc"
sudo install -Dm644 assets/fastfetch/config.jsonc "$ROOTFS/etc/skel/.config/fastfetch/config.jsonc"

echo "=== [4/8] FETCHING GRUB, efibootmgr, dosfstools AND fastfetch FROM NIXPKGS ==="
# These are the target image's own boot/install tools, fetched with goget itself (--root/--system
# populate a real, ordinary "system" goget profile, exactly like a booted system's own
# `sudo goget install` would) into a cached, gitignored work dir, then merged into the squashfs
# stage at step 6 — never into the tracked rootfs/. goget resolves the full runtime dependency
# closure itself (that's its whole job), so there is no manual shared-library bookkeeping here.
"$GOGET" install --root "$BOOT_WORK" --system -y grub efibootmgr dosfstools fastfetch

echo "=== [5/8] PREPARING ISO WORKSPACE ==="
if mount | grep -q " $ROOTFS/"; then
    echo "ERROR: something is still mounted under $ROOTFS; refusing to pack it"; exit 1
fi
sudo rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE/live" "$WORKSPACE/boot/grub"

echo "=== [5b/8] BUILDING THE FIRMWARE OVERLAY FROM NIXPKGS ==="
# Built-in drivers load firmware while the kernel initialises, so it goes into the initramfs;
# it also stays in the squashfs for devices plugged in later.
WORK=$FW_WORK "$BUILD_DIR/tools/firmware-overlay/build-overlay.sh"
ROOTFS=$ROOTFS python3 "$BUILD_DIR/tools/overlay-common/mkcpio.py" "$FW_WORK/ov5.cpio" "$FW_WORK/ov5"

echo "=== [5c/8] BUILDING THE BASE SERVICES OVERLAY FROM NIXPKGS ==="
# Bluetooth, audio, time sync, power profiles, printing, firmware updates, Flatpak, a default
# firewall, locales/input methods -- everyday daemons, no desktop. See tools/base-overlay/.
WORK=$BASE_WORK ROOTFS=$ROOTFS "$BUILD_DIR/tools/base-overlay/build-overlay.sh"

echo "=== [6/8] BUILDING THE SQUASHFS AND THE INITRAMFS ==="
STAGE=$WORKSPACE/stage
sudo mkdir -p "$STAGE"
sudo cp -a "$ROOTFS/." "$STAGE/"
sudo "$BUILD_DIR/tools/overlay-common/strip-gentoo.sh" "$STAGE"
# goget installs nixpkgs packages into /nix/store (group-writable for wheel) and finds them through a profile script
sudo mkdir -p "$STAGE/nix/store" "$STAGE/nix/var/goget"
sudo chmod 1775 "$STAGE/nix/store"; sudo chmod 2775 "$STAGE/nix/var/goget"
WG=$(sed -n 's/^wheel:[^:]*:\([0-9]*\):.*/\1/p' "$STAGE/etc/group"); [ -z "$WG" ] || sudo chown -R "0:$WG" "$STAGE/nix"
sudo install -Dm644 "$BUILD_DIR/tools/overlay-common/goget-profile.sh" "$STAGE/etc/profile.d/goget.sh"
sudo cp -a "$FW_WORK/ov5/." "$STAGE/"
# merge the boot-tools profile (grub/efibootmgr/dosfstools/fastfetch) into the image's own /nix
sudo mkdir -p "$STAGE/nix"
sudo cp -a "$BOOT_WORK/nix/." "$STAGE/nix/"
for b in grub-install grub-mkimage grub-probe grub-editenv grub-set-default grub-reboot \
         efibootmgr efibootdump mkfs.fat mkfs.vfat mkfs.msdos fastfetch; do
    sudo ln -sf /nix/var/goget/profiles/system/current/bin/"$b" "$STAGE/usr/bin/$b"
done
sudo mkdir -p "$STAGE/usr/lib" "$STAGE/usr/share"
sudo ln -sf /nix/var/goget/profiles/system/current/lib/grub "$STAGE/usr/lib/grub"
sudo ln -sf /nix/var/goget/profiles/system/current/share/grub "$STAGE/usr/share/grub"
# merge the base-services overlay (bluetooth/audio/chrony/power/cups/fwupd/flatpak/firewall/locales)
sudo cp -a "$BASE_WORK/ov3/." "$STAGE/"
sudo cp -a "$BASE_WORK/ov4/." "$STAGE/"
echo "$IMAGE_VERSION" | sudo tee "$STAGE/usr/share/systemlinux/image-version" >/dev/null
sudo install -Dm644 "$KERNEL" "$STAGE/boot/vmlinuz"
sudo mksquashfs "$STAGE" "$WORKSPACE/live/rootfs.squashfs" -comp zstd -Xcompression-level 19 -b 1M -noappend -no-xattrs
sudo rm -rf "$STAGE"
sudo chown "$USER" "$WORKSPACE/live/rootfs.squashfs"
ls -lh "$WORKSPACE/live/rootfs.squashfs"
BUILD_ID="$IMAGE_VERSION-$(date +%s)"
echo "$BUILD_ID" > "$WORKSPACE/live/build-id"
BUILD_ID=$BUILD_ID WORK=$HOME/.cache/systemlinux-initrd FW_CPIO="$FW_WORK/ov5.cpio" "$BUILD_DIR/tools/live-image/build-initrd.sh" "$WORKSPACE/live/initrd.img"

echo "=== [7/8] COPYING KERNEL AND WRITING grub.cfg ==="
cp "$KERNEL" "$WORKSPACE/live/vmlinuz"
cat > "$WORKSPACE/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=3

menuentry "systemLinux $IMAGE_VERSION" {
    # Use the device GRUB booted from (works under Ventoy's loopback); only search if the
    # kernel isn't there, so another disk's /live/vmlinuz is never picked up.
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz quiet loglevel=3 console=tty0
    initrd /live/initrd.img
}

menuentry "systemLinux $IMAGE_VERSION (copy to RAM)" {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz systemlinux.toram=1 quiet loglevel=3 console=tty0
    initrd /live/initrd.img
}

menuentry "systemLinux $IMAGE_VERSION (debug shell)" {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz systemlinux.debug=1 console=tty0
    initrd /live/initrd.img
}
GRUBEOF
"$GRUB_SCRIPT_CHECK" "$WORKSPACE/boot/grub/grub.cfg"

echo "=== [8/8] MASTERING ISO ==="
"$GRUB_MKRESCUE" -o "$ISO" "$WORKSPACE"
sudo rm -rf "$WORKSPACE"
sha256sum "$ISO"
echo "SUCCESS: $ISO"
