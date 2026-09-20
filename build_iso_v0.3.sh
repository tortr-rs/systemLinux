#!/bin/bash
# systemLinux v0.3 ISO build: systemL init, goget, installer tools, kernel.
# Run from a normal terminal (sudo needs a password prompt): ./build_iso_v0.3.sh
set -euo pipefail

BUILD_DIR=/home/torter/systemlinux
ROOTFS=$BUILD_DIR/rootfs
WORKSPACE=$BUILD_DIR/iso_workspace
KERNEL=$BUILD_DIR/systemlinux-distro/linux-7.2.6/arch/x86/boot/bzImage
ISO=${ISO:-$BUILD_DIR/systemlinux-v0.3.iso}
cd "$BUILD_DIR"

[ -f "$KERNEL" ] || { echo "ERROR: kernel not found at $KERNEL"; exit 1; }

echo "=== [1/7] COMPILING systemL AND goget ==="
make -C ./systemL
make -C ./goget

echo "=== [2/7] INSTALLING systemL, goget AND init LINKS INTO ROOTFS ==="
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

echo "=== [3/7] INJECTING GRUB, efibootmgr, dosfstools FROM DEBIAN ==="
# Raw Debian binaries/modules go straight into the rootfs. Debian's libs
# (x86_64-linux-gnu) map to this rootfs's /usr/lib64, and /usr/sbin is a
# symlink to bin. util-linux (blkid, blockdev, sfdisk) and e2fsprogs (mkfs.ext4)
# are NOT replaced: the rootfs already has newer builds (2.42 / 1.47.4) than
# Debian's, and swapping binaries without their matching libs would break them.
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
# Tools that must already exist from the base system
for t in blkid blockdev sfdisk wipefs mkfs.ext4 mkfs.vfat efibootdump fatlabel; do
    [ -e "$ROOTFS/usr/bin/$t" ] || { echo "ERROR: $t missing from rootfs"; missing=1; }
done
[ "$missing" = 0 ] || exit 1

echo "=== [4/7] PREPARING ISO WORKSPACE ==="
sudo rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE/live" "$WORKSPACE/boot/grub"

echo "=== [5/7] PACKING ROOTFS INTO INITRD ==="
if mount | grep -q " $ROOTFS/"; then
    echo "ERROR: something is still mounted under $ROOTFS; refusing to pack it"; exit 1
fi
(cd "$ROOTFS" && sudo find . -print0 | sudo cpio --null -o --format=newc --quiet | gzip -9 > "$WORKSPACE/live/initrd.img")

echo "=== [6/7] COPYING KERNEL AND WRITING grub.cfg ==="
cp "$KERNEL" "$WORKSPACE/live/vmlinuz"
cat > "$WORKSPACE/boot/grub/grub.cfg" << 'GRUBEOF'
set default=0
set timeout=3

menuentry "systemLinux v0.3" {
    search --no-floppy --set=root --file /live/vmlinuz
    linux /live/vmlinuz ramdisk_size=4000000 root=/dev/ram0 rw console=tty0 init=/sbin/systemL
    initrd /live/initrd.img
}
GRUBEOF

echo "=== [7/7] MASTERING ISO ==="
grub-mkrescue -o "$ISO" "$WORKSPACE"
sudo rm -rf "$WORKSPACE"

echo "SUCCESS: $ISO"
