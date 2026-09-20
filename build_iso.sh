#!/bin/bash
# systemLinux v0.4 ISO build: systemL init, goget, boot/disk tools, kernel, optional XFCE.
#
#   VARIANT=minimal ./build_iso.sh    -> systemlinux-v0.4-minimal.iso  (root shell, console only)
#   VARIANT=xfce    ./build_iso.sh    -> systemlinux-v0.4-xfce.iso     (live XFCE desktop)
#
# Run from a normal terminal (sudo needs a password prompt). Needs a Debian host with
# grub-mkrescue, xorriso, mtools, zstd, cpio and (for xfce) apt.
set -euo pipefail

VARIANT=${VARIANT:-minimal}
case "$VARIANT" in minimal|xfce) ;; *) echo "VARIANT must be minimal or xfce"; exit 1 ;; esac

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOTFS=$BUILD_DIR/rootfs
WORKSPACE=$BUILD_DIR/iso_workspace
KERNEL=${KERNEL:-$BUILD_DIR/systemlinux-distro/linux-7.2.6/arch/x86/boot/bzImage}
ISO=${ISO:-$BUILD_DIR/systemlinux-v0.4-$VARIANT.iso}
XFCE_WORK=${XFCE_WORK:-$HOME/.cache/systemlinux-xfce}
cd "$BUILD_DIR"

[ -f "$KERNEL" ] || { echo "ERROR: kernel not found at $KERNEL"; exit 1; }

echo "=== [1/8] COMPILING systemL AND goget ==="
make -C ./systemL
make -C ./goget

echo "=== [2/8] INSTALLING systemL, goget AND init LINKS INTO ROOTFS ==="
# /sbin is a symlink to usr/bin in this rootfs, so this lands in usr/bin
sudo install -Dm755 ./systemL/systemL "$ROOTFS/sbin/systemL"
sudo install -Dm755 ./goget/goget "$ROOTFS/usr/bin/goget"
sudo install -Dm755 ./goget/goget "$ROOTFS/usr/local/bin/goget"
sudo rm -f "$ROOTFS/init" "$ROOTFS/sbin/init"
sudo ln -sf sbin/systemL "$ROOTFS/init"
sudo ln -sf systemL "$ROOTFS/sbin/init"
# power commands were symlinks to systemctl; systemL handles them itself
for n in reboot poweroff halt shutdown; do
    sudo ln -sf systemL "$ROOTFS/usr/bin/$n"
done
sudo install -Dm644 "$KERNEL" "$ROOTFS/boot/vmlinuz"

echo "=== [3/8] ROOTFS FIXES AND BRANDING ==="
# D-Bus activation needs the launch helper setuid root (it was owned by the build user with no setuid bit)
sudo chown root:messagebus "$ROOTFS/usr/libexec/dbus-daemon-launch-helper"
sudo chmod 4750 "$ROOTFS/usr/libexec/dbus-daemon-launch-helper"
# systemd's shell-integration script prints escape-code garbage without systemd
sudo rm -f "$ROOTFS/etc/profile.d/80-systemd-osc-context.sh"
# issue, os-release, release files and the login banner
sudo ./goget/goget provision "$ROOTFS"

echo "=== [4/8] INJECTING GRUB, efibootmgr, dosfstools FROM DEBIAN ==="
# Raw Debian binaries/modules go straight into the rootfs. Debian's libs
# (x86_64-linux-gnu) map to this rootfs's /usr/lib64, and /usr/sbin is a
# symlink to bin. util-linux and e2fsprogs are NOT replaced: the rootfs already
# has newer builds than Debian's.
need_inject=0
for f in usr/bin/grub-mkimage usr/bin/efibootmgr usr/bin/mkfs.fat usr/sbin/grub-install \
         usr/lib/grub/i386-pc/normal.mod usr/lib/grub/x86_64-efi/normal.mod \
         usr/lib64/libdevmapper.so.1.02.1 usr/lib64/libselinux.so.1 usr/lib64/libfuse3.so.4; do
    [ -e "$ROOTFS/$f" ] || need_inject=1
done
if [ "$need_inject" = 1 ]; then
    DEBTMP=$(mktemp -d)
    trap 'rm -rf "$DEBTMP"' EXIT
    (cd "$DEBTMP" && apt-get download \
        grub-common grub2-common grub-pc-bin grub-efi-amd64-bin \
        efibootmgr dosfstools \
        libdevmapper1.02.1 libselinux1 libfuse3-4)
    for deb in "$DEBTMP"/*.deb; do dpkg-deb -x "$deb" "$DEBTMP/root"; done
    R="$DEBTMP/root"
    sudo cp -a "$R/usr/bin/." "$ROOTFS/usr/bin/"
    sudo cp -a "$R/usr/sbin/." "$ROOTFS/usr/sbin/"
    sudo mkdir -p "$ROOTFS/usr/lib" "$ROOTFS/usr/share" "$ROOTFS/usr/lib64"
    sudo cp -a "$R/usr/lib/grub" "$ROOTFS/usr/lib/"
    sudo cp -a "$R/usr/share/grub" "$ROOTFS/usr/share/"
    sudo cp -a "$R"/usr/lib/x86_64-linux-gnu/. "$ROOTFS/usr/lib64/"
    rm -rf "$DEBTMP"
    trap - EXIT
fi

# Everything the injected binaries link against must resolve inside the rootfs
missing=0
for b in usr/sbin/grub-install usr/sbin/grub-probe usr/bin/grub-mkimage usr/bin/efibootmgr \
         usr/bin/mkfs.fat usr/bin/grub-mount; do
    [ -e "$ROOTFS/$b" ] || { echo "ERROR: $b missing from rootfs"; missing=1; continue; }
    for lib in $(readelf -d "$ROOTFS/$b" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
        [ -e "$ROOTFS/usr/lib64/$lib" ] || [ -e "$ROOTFS/lib64/$lib" ] || { echo "ERROR: $b needs $lib, not in rootfs"; missing=1; }
    done
done
for t in blkid blockdev sfdisk wipefs mkfs.ext4 mkfs.vfat efibootdump fatlabel; do
    [ -e "$ROOTFS/usr/bin/$t" ] || { echo "ERROR: $t missing from rootfs"; missing=1; }
done
[ "$missing" = 0 ] || exit 1

echo "=== [5/8] PREPARING ISO WORKSPACE ==="
if mount | grep -q " $ROOTFS/"; then
    echo "ERROR: something is still mounted under $ROOTFS; refusing to pack it"; exit 1
fi
sudo rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE/live" "$WORKSPACE/boot/grub"

OVERLAY=""
if [ "$VARIANT" = xfce ]; then
    echo "=== [5b/8] BUILDING THE XFCE OVERLAY FROM DEBIAN ==="
    WORK=$XFCE_WORK ROOTFS=$ROOTFS "$BUILD_DIR/tools/xfce-overlay/build-overlay.sh"
    OVERLAY=1
fi

echo "=== [6/8] PACKING THE INITRD (zstd) ==="
# The kernel accepts concatenated compressed cpio archives, so the XFCE overlay is appended.
# zstd keeps the initrd small enough for GRUB to load it into one contiguous block of memory.
(cd "$ROOTFS" && sudo find . -print0 | sudo cpio --null -o --format=newc --quiet | zstd -19 -T0 -q > "$WORKSPACE/live/initrd.img")
if [ -n "$OVERLAY" ]; then
    WORK=$XFCE_WORK ROOTFS=$ROOTFS python3 "$BUILD_DIR/tools/xfce-overlay/mkcpio.py" "$WORKSPACE/overlay.cpio.gz" \
        "$XFCE_WORK/ov3" "$XFCE_WORK/ov4"
    cat "$WORKSPACE/overlay.cpio.gz" >> "$WORKSPACE/live/initrd.img"
    rm -f "$WORKSPACE/overlay.cpio.gz"
fi

echo "=== [7/8] COPYING KERNEL AND WRITING grub.cfg ==="
cp "$KERNEL" "$WORKSPACE/live/vmlinuz"
cat > "$WORKSPACE/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=3

menuentry "systemLinux v0.4 ($VARIANT)" {
    # Use the device GRUB booted from (works under Ventoy's loopback); only search if the
    # kernel isn't there, so another disk's /live/vmlinuz is never picked up.
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz root=/dev/ram0 rw console=tty0 init=/sbin/systemL
    initrd /live/initrd.img
}
GRUBEOF
grub-script-check "$WORKSPACE/boot/grub/grub.cfg"

echo "=== [8/8] MASTERING ISO ==="
grub-mkrescue -o "$ISO" "$WORKSPACE"
sudo rm -rf "$WORKSPACE"
sha256sum "$ISO"
echo "SUCCESS: $ISO"
