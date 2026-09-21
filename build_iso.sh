#!/bin/bash
# systemLinux v0.4 ISO build: a normal live ISO (small initramfs + /live/rootfs.squashfs, mounted
# with an overlayfs; nothing is loaded into a RAM disk), with systemL as init, goget, boot/disk
# tools, the full-driver kernel, firmware and (for xfce) the desktop, installer and Firefox.
#
#   VARIANT=minimal ./build_iso.sh    -> systemlinux-v0.4-minimal.iso  (root shell, console only)
#   VARIANT=xfce    ./build_iso.sh    -> systemlinux-v0.4-xfce.iso     (live XFCE desktop)
#   VARIANT=gnome   ./build_iso.sh    -> systemlinux-v0.4-gnome.iso    (live GNOME desktop on elogind)
#
# Run from a normal terminal (sudo needs a password prompt). Needs a Debian host with
# grub-mkrescue, xorriso, mtools, squashfs-tools, cpio and apt.
set -euo pipefail

VARIANT=${VARIANT:-minimal}
case "$VARIANT" in minimal|xfce|gnome) ;; *) echo "VARIANT must be minimal, xfce or gnome"; exit 1 ;; esac

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOTFS=$BUILD_DIR/rootfs
WORKSPACE=$BUILD_DIR/iso_workspace
# the "full" kernel is the same Linux 7.2.6 with drivers for almost everything built in
KERNEL=${KERNEL:-$BUILD_DIR/tools/kernel-full/vmlinuz-7.2.6-full}
ISO=${ISO:-$BUILD_DIR/systemlinux-v0.4-$VARIANT.iso}
XFCE_WORK=${XFCE_WORK:-$HOME/.cache/systemlinux-xfce}
FW_WORK=${FW_WORK:-$HOME/.cache/systemlinux-firmware}
GNOME_WORK=${GNOME_WORK:-$HOME/.cache/systemlinux-gnome}
cd "$BUILD_DIR"

echo "=== [1/8] COMPILING systemL, goget AND THE FULL KERNEL ==="
if [ ! -f "$KERNEL" ]; then "$BUILD_DIR/tools/kernel-full/build-kernel.sh"; fi
[ -f "$KERNEL" ] || { echo "ERROR: kernel not found at $KERNEL"; exit 1; }
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
# GNU bash is the system shell (/bin/bash and /bin/sh); the bbash fork stays installed as its own command.
# Built static, so it does not depend on the base's libtinfo. The libarchive tools (BSD tar and friends)
# are removed: GNU tar is the tar.
[ -x tools/gnu-bash/bash ] || tools/gnu-bash/build.sh
sudo install -Dm755 tools/gnu-bash/bash "$ROOTFS/usr/bin/bash"
sudo ln -sf bash "$ROOTFS/usr/bin/sh"
sudo rm -f "$ROOTFS"/usr/bin/bsdtar "$ROOTFS"/usr/bin/bsdcat "$ROOTFS"/usr/bin/bsdcpio "$ROOTFS"/usr/bin/bsdunzip
# issue, os-release, release files and the login banner (GNU/Linux branding)
sudo ./goget/goget provision "$ROOTFS"
# fastfetch (Debian build; its only extra library is libyyjson) so the cat logo below has a program to show it
if [ ! -e "$ROOTFS/usr/bin/fastfetch" ]; then
    FFTMP=$(mktemp -d)
    (cd "$FFTMP" && apt-get download fastfetch libyyjson0 >/dev/null)
    for deb in "$FFTMP"/*.deb; do dpkg-deb -x "$deb" "$FFTMP/root"; done
    sudo install -Dm755 "$FFTMP/root/usr/bin/fastfetch" "$ROOTFS/usr/bin/fastfetch"
    sudo cp -a "$FFTMP/root/usr/share/fastfetch" "$ROOTFS/usr/share/"
    sudo mkdir -p "$ROOTFS/usr/lib64"
    sudo cp -a "$FFTMP"/root/usr/lib/x86_64-linux-gnu/libyyjson.so.0* "$ROOTFS/usr/lib64/"
    rm -rf "$FFTMP"
fi
# fastfetch: the cat logo as ASCII art (assets/fastfetch/make-logo.py regenerates it from assets/logo.png),
# for root and, through /etc/skel, for every new user
sudo install -Dm644 assets/fastfetch/logo.txt "$ROOTFS/usr/share/systemlinux/fastfetch-logo.txt"
sudo install -Dm644 assets/fastfetch/config.jsonc "$ROOTFS/root/.config/fastfetch/config.jsonc"
sudo install -Dm644 assets/fastfetch/config.jsonc "$ROOTFS/etc/skel/.config/fastfetch/config.jsonc"

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

echo "=== [5b/8] BUILDING THE FIRMWARE OVERLAY FROM DEBIAN ==="
# Built-in drivers load firmware while the kernel initialises, so it goes into the initramfs;
# it also stays in the squashfs for devices plugged in later.
WORK=$FW_WORK "$BUILD_DIR/tools/firmware-overlay/build-overlay.sh"
ROOTFS=$ROOTFS python3 "$BUILD_DIR/tools/xfce-overlay/mkcpio.py" "$FW_WORK/ov5.cpio" "$FW_WORK/ov5"

if [ "$VARIANT" = xfce ]; then
    echo "=== [5c/8] BUILDING THE XFCE OVERLAY FROM DEBIAN ==="
    WORK=$XFCE_WORK ROOTFS=$ROOTFS "$BUILD_DIR/tools/xfce-overlay/build-overlay.sh"
fi
if [ "$VARIANT" = gnome ]; then
    echo "=== [5c/8] BUILDING THE GNOME OVERLAY FROM DEBIAN ==="
    WORK=$GNOME_WORK ROOTFS=$ROOTFS "$BUILD_DIR/tools/gnome-overlay/build-overlay.sh"
fi

echo "=== [6/8] BUILDING THE SQUASHFS AND THE INITRAMFS ==="
STAGE=$WORKSPACE/stage
sudo mkdir -p "$STAGE"
sudo cp -a "$ROOTFS/." "$STAGE/"
sudo cp -a "$FW_WORK/ov5/." "$STAGE/"
if [ "$VARIANT" = xfce ]; then
    sudo cp -a "$XFCE_WORK/ov3/." "$STAGE/"
    sudo cp -a "$XFCE_WORK/ov4/." "$STAGE/"
fi
if [ "$VARIANT" = gnome ]; then
    sudo cp -a "$GNOME_WORK/ov3/." "$STAGE/"
    sudo cp -a "$GNOME_WORK/ov4/." "$STAGE/"
    # the live user GNOME logs in as (systemL autologin on tty1); the installer removes it again
    sudo useradd -R "$STAGE" -m -u 1000 -U -s /bin/bash -c "Live user" -G wheel,audio,video,input,users,plugdev live
    sudo usermod -R "$STAGE" -p '' live
    # slim the GNOME image: GitHub release files must stay under 2 GiB. Nothing a user needs is removed
    # (the Go compiler stays); the Go bootstrap toolchain, docs, base translations and extra wallpapers go.
    sudo rm -rf "$STAGE/usr/lib/go-bootstrap" "$STAGE/usr/share/locale" "$STAGE/usr/share/man" "$STAGE/usr/share/doc" \
        "$STAGE/usr/share/gtk-doc" "$STAGE/usr/share/i18n" "$STAGE/usr/share/desktop-base" \
        "$STAGE/usr/lib/x86_64-linux-gnu/perl" "$STAGE/usr/share/vulkan"
    sudo find "$STAGE/usr/share/backgrounds" -mindepth 1 -maxdepth 1 ! -name systemlinux -exec rm -rf {} +
    sudo rm -f "$STAGE"/usr/lib/x86_64-linux-gnu/libvulkan_*.so* "$STAGE"/usr/lib64/libvulkan_*.so*
fi
sudo install -Dm644 "$KERNEL" "$STAGE/boot/vmlinuz"
sudo mksquashfs "$STAGE" "$WORKSPACE/live/rootfs.squashfs" -comp zstd -Xcompression-level 19 -b 1M -noappend -no-xattrs
sudo rm -rf "$STAGE"
sudo chown "$USER" "$WORKSPACE/live/rootfs.squashfs"
ls -lh "$WORKSPACE/live/rootfs.squashfs"
WORK=$HOME/.cache/systemlinux-initrd FW_CPIO="$FW_WORK/ov5.cpio" "$BUILD_DIR/tools/live-image/build-initrd.sh" "$WORKSPACE/live/initrd.img"

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
    linux /live/vmlinuz systeml.live=1 quiet loglevel=3 console=tty0
    initrd /live/initrd.img
}

menuentry "systemLinux v0.4 ($VARIANT, copy to RAM)" {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz systeml.live=1 systeml.toram=1 quiet loglevel=3 console=tty0
    initrd /live/initrd.img
}

menuentry "systemLinux v0.4 ($VARIANT, debug shell)" {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz systeml.live=1 systeml.debug=1 console=tty0
    initrd /live/initrd.img
}
GRUBEOF
grub-script-check "$WORKSPACE/boot/grub/grub.cfg"

echo "=== [8/8] MASTERING ISO ==="
grub-mkrescue -o "$ISO" "$WORKSPACE"
sudo rm -rf "$WORKSPACE"
sha256sum "$ISO"
echo "SUCCESS: $ISO"
