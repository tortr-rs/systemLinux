#!/bin/bash
# systemLinux ISO build: a minimal live installer ISO (small initramfs + /live/rootfs.squashfs, mounted
# with an overlayfs; nothing is loaded into a RAM disk): the latest Ubuntu generic kernel plus the bare minimum
# needed to run the installer (dinit, eudev, NetworkManager, disk/boot tools, `get`). No firmware, desktop,
# daemons, docs, locales, compilers or language runtimes. After installing, `get --profile build-toolchain`
# (and common-build-deps, lang-runtimes, ...) adds the build stack; `get URL` builds source tarballs.
#
#   ./build_iso.sh    (checks ports and dinit services first, then builds)  -> systemLinux-0.2.2-x86_64.iso + .sha256  (root shell, console only, installable with the handbook)
#
# Run from a normal terminal (sudo needs a password prompt). Works from any Linux host with
# grub2, xorriso, mtools, squashfs-tools and cpio on PATH (install them with your host's own
# package manager, e.g. `emerge sys-boot/grub app-cdr/xorriso sys-fs/mtools sys-fs/squashfs-tools
# app-arch/cpio` on Gentoo, `apt install grub2 xorriso mtools squashfs-tools cpio` on Debian, or
# equivalent). The installer's own boot tools (grub, efibootmgr, mkfs.fat, cryptsetup, busybox) are
# copied from the build host together with their libraries. The ISO is always a hybrid BIOS+UEFI image:
# grub-pc-bin (i386-pc) and grub-efi-amd64-bin (x86_64-efi) are both required, and the build stops if one is missing.
# dinit (PID 1) is built from a pinned release tarball by tools/dinit/build.sh (needs g++, make and curl).
# There is no systemd: eudev (tools/eudev/build.sh; needs gperf, pkg-config, libkmod and libblkid headers) is the
# device manager, and tools/libsystemd-stub builds the no-op libsystemd.so.0 the prebuilt programs still link to.
# The kernel is the newest Ubuntu linux-image-generic, downloaded and verified by tools/ubuntu-kernel/fetch.sh
# (pin a series with UBUNTU_SERIES=..., or set KERNEL=/path/to/vmlinuz and MODULES_ROOT to use another kernel).
set -euo pipefail

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
ROOTFS=$BUILD_DIR/rootfs
WORKSPACE=$BUILD_DIR/iso_workspace
KERNEL=${KERNEL:-}
IMAGE_VERSION=$(cat "$BUILD_DIR/VERSION")
PROFILES_OUT=${PROFILES_OUT:-$BUILD_DIR/profiles-out}
ISO=${ISO:-$BUILD_DIR/systemLinux-$IMAGE_VERSION-x86_64.iso}
cd "$BUILD_DIR"
# fail early, with the fix, instead of halfway through the kernel build
missing=
for t in xorriso mksquashfs mformat cpio make gcc g++ curl busybox cryptsetup efibootmgr mkfs.fat grub-install grub-mkimage \
         gperf pkg-config depmod xz zstd ar nm readelf; do
    command -v "$t" >/dev/null || missing="$missing $t"
done
pkg-config --exists libkmod blkid 2>/dev/null || missing="$missing libkmod-dev/libblkid-dev(for eudev)"
command -v grub-mkrescue >/dev/null || command -v grub2-mkrescue >/dev/null || missing="$missing grub-mkrescue"
command -v grub-script-check >/dev/null || command -v grub2-script-check >/dev/null || missing="$missing grub-script-check"
# both GRUB platforms are needed: i386-pc for legacy BIOS, x86_64-efi for UEFI (the installer ships both too)
for plat in i386-pc x86_64-efi; do
    found=
    for d in /usr/lib/grub /usr/lib64/grub /usr/lib/grub2 /usr/lib64/grub2 /usr/share/grub; do
        [ -d "$d/$plat" ] && { found=1; break; }
    done
    [ -n "$found" ] || missing="$missing grub-$plat-modules(no $plat dir under /usr/lib*/grub*)"
done
if [ -n "$missing" ]; then
    echo "ERROR: missing build tools:$missing"
    echo "  (the installer needs the grub-* command names; on Fedora add symlinks from grub2-*)"
    echo "  (grub-<platform>-modules = GRUB platform files: Debian grub-pc-bin / grub-efi-amd64-bin, Fedora grub2-pc-modules / grub2-efi-x64-modules)"
    echo "  Fedora: sudo dnf install xorriso squashfs-tools mtools cpio busybox cryptsetup efibootmgr dosfstools grub2-efi-x64 grub2-efi-x64-modules grub2-pc grub2-pc-modules grub2-tools gcc-c++ curl gperf pkgconf kmod kmod-devel libblkid-devel zstd xz grub2-tools-extra"
    echo "  Debian: sudo apt install xorriso squashfs-tools mtools cpio busybox cryptsetup efibootmgr dosfstools grub-efi-amd64-bin grub-pc-bin g++ curl gperf pkg-config kmod libkmod-dev libblkid-dev zstd xz-utils binutils grub-common"
    exit 1
fi
# Fedora and friends name the GRUB tools grub2-*
GRUB_MKRESCUE=$(command -v grub-mkrescue || command -v grub2-mkrescue || echo grub-mkrescue)
GRUB_SCRIPT_CHECK=$(command -v grub-script-check || command -v grub2-script-check || echo grub-script-check)
GRUB_MKIMAGE=$(command -v grub-mkimage || command -v grub2-mkimage || echo grub-mkimage)
GRUB_BIOS_SETUP=$(command -v grub-bios-setup || command -v grub2-bios-setup || echo grub-bios-setup)   # grub-install --target=i386-pc runs it

echo "=== [0/7] CHECKING PORTS AND dinit SERVICES ==="
"$BUILD_DIR/tools/ports-check.sh" 2>&1 | grep -v 'missing sha256' || { echo "ERROR: ports check failed"; exit 1; }
[ "${PIPESTATUS[0]}" = 0 ] || exit 1
echo "=== [1/7] FETCHING THE LATEST UBUNTU KERNEL ==="
if [ -z "$KERNEL" ]; then
    KDIR=$(mktemp -d)
    trap 'rm -rf "$KDIR"' EXIT
    "$BUILD_DIR/tools/ubuntu-kernel/fetch.sh" "$KDIR"
    KERNEL=$KDIR/root/boot/vmlinuz-$(cat "$KDIR/kver")
    MODULES_ROOT=$KDIR/root
fi
[ -n "$KERNEL" ] && [ -f "$KERNEL" ] || { echo "ERROR: kernel not found at $KERNEL (set KERNEL to a prebuilt kernel image)"; exit 1; }
KVER=$([ "${KERNEL##*/}" != "${KERNEL##*/vmlinuz-}" ] && echo "${KERNEL##*/vmlinuz-}" || uname -r)
MODULES_ROOT=${MODULES_ROOT:-}
# Ubuntu's linux-modules package ships no modules.dep (its postinst runs depmod)
if [ -d "$MODULES_ROOT/lib/modules/$KVER" ] && [ ! -f "$MODULES_ROOT/lib/modules/$KVER/modules.dep" ]; then
    depmod -b "$MODULES_ROOT" "$KVER"
fi
echo "kernel: $KVER ($KERNEL)"

echo "=== [2/7] INSTALLING get AND dinit INTO ROOTFS ==="
sudo install -Dm755 ./get "$ROOTFS/usr/local/bin/get"
sudo install -Dm755 ./tools/validate-build-ready.sh "$ROOTFS/usr/local/bin/validate-build-ready"
# the ports tree, so `get category/name` works offline; `get --sync` updates it from the latest release's ports.tar.xz
sudo rm -rf "$ROOTFS/usr/ports"
sudo cp -r ./ports "$ROOTFS/usr/ports"
sudo chown -R 0:0 "$ROOTFS/usr/ports"
# dinit is PID 1 and the only init system; systemd is removed completely
sudo rm -f "$ROOTFS/init" "$ROOTFS/sbin/init" "$ROOTFS/sbin/lenine"
sudo "$BUILD_DIR/tools/dinit/build.sh" "$ROOTFS"
sudo ln -sf usr/bin/dinit "$ROOTFS/init"
sudo ln -sf dinit "$ROOTFS/usr/bin/init"
# eudev replaces systemd-udevd and systemd's libudev; libsystemd.so.0 becomes a no-op stub (no systemd code) for
# the prebuilt programs still linked to it (dbus, NetworkManager, util-linux, ...)
sudo "$BUILD_DIR/tools/eudev/build.sh" "$ROOTFS"
sudo "$BUILD_DIR/tools/libsystemd-stub/build.sh" "$ROOTFS"
# the boot target, services and helper scripts (rootfs/etc/dinit.d, rootfs/usr/lib/dinit) are part of rootfs/ itself
"$BUILD_DIR/tools/check-no-systemd.sh" "$ROOTFS"
DINIT_CHECK="$ROOTFS/usr/bin/dinit-check" "$BUILD_DIR/tools/dinit/check-services.sh"
sudo install -Dm644 "$KERNEL" "$ROOTFS/boot/vmlinuz"

echo "=== [3/7] ROOTFS FIXES AND BRANDING ==="
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
sudo SYSTEMLINUX_VERSION="$IMAGE_VERSION" ./tools/installer/usr/local/bin/systemlinux-provision "$ROOTFS"

echo "=== [4/7] PREPARING ISO WORKSPACE ==="
if mount | grep -q " $ROOTFS/"; then
    echo "ERROR: something is still mounted under $ROOTFS; refusing to pack it"; exit 1
fi
sudo rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE/live" "$WORKSPACE/boot/grub"

echo "=== [5/7] BUILDING THE SQUASHFS AND THE INITRAMFS ==="
STAGE=$WORKSPACE/stage
sudo mkdir -p "$STAGE"
sudo cp -a "$ROOTFS/." "$STAGE/"
sudo "$BUILD_DIR/tools/overlay-common/strip-gentoo.sh" "$STAGE"
# the installer's boot/disk tools come from the build host; they run on the host's libraries, kept apart in
# /usr/lib/systemlinux-host so they never replace the image's own glibc and libraries (they used to land in
# /usr/lib: the host's 64-bit glibc over the 32-bit one, which broke every program with a ../lib RUNPATH, e.g. cargo)
sudo "$BUILD_DIR/tools/overlay-common/copy-host-tools.sh" "$STAGE" grub-install "$GRUB_MKIMAGE" grub-probe grub-editenv \
    grub-set-default grub-reboot efibootmgr mkfs.fat "$GRUB_BIOS_SETUP"
GRUBDATA=0
for d in /usr/lib/grub /usr/lib64/grub /usr/share/grub /usr/lib/grub2 /usr/share/grub2; do
    if [ -d "$d" ]; then sudo mkdir -p "$STAGE$d"; sudo cp -a "$d/." "$STAGE$d/"; GRUBDATA=1; fi
done
[ "$GRUBDATA" = 1 ] || { echo "ERROR: no GRUB platform files (x86_64-efi) found on the build host"; exit 1; }
MKFS=$(readlink -f "$(command -v mkfs.fat)")
sudo ln -sf "$(basename "$MKFS")" "$STAGE$(dirname "$MKFS")/mkfs.vfat"
# the installer itself, and the hostname
sudo cp -a "$BUILD_DIR/tools/installer/." "$STAGE/"
sudo chmod 755 "$STAGE"/usr/local/bin/systemlinux-*
sudo "$BUILD_DIR/tools/live-image/strip-live.sh" "$STAGE"
# the build toolchain, build dependencies and language runtimes are post-install profiles, not live media
sudo "$BUILD_DIR/tools/profiles/profiles.sh" strip "$STAGE"
# The build-toolchain profile takes all of usr/lib/gcc, but the GCC runtime libraries in it are not build tools:
# dinit (PID 1) and every other C++ program need libstdc++/libgcc_s. Without them the kernel panics at boot.
for d in "$ROOTFS"/usr/lib/gcc/*/*/; do
    for l in libstdc++.so.6 libgcc_s.so.1 libatomic.so.1 libgomp.so.1 libitm.so.1 libquadmath.so.0; do
        [ -e "$d$l" ] && sudo cp -aL "$d$l" "$STAGE/usr/lib64/$l"
    done
done
sudo ldconfig -r "$STAGE"
# pkg-config files still naming libsystemd (dbus-1.pc: "Requires.private: libsystemd >= 209") would make
# pkg-config fail for every build that uses them, since systemd is gone
for pc in "$STAGE"/usr/lib64/pkgconfig/*.pc "$STAGE"/usr/share/pkgconfig/*.pc; do
    [ -f "$pc" ] && grep -q '^Requires.*libsystemd' "$pc" || continue
    sudo sed -i -E '/^Requires/{s/,?[[:space:]]*libsystemd([[:space:]]*[<>=]+[[:space:]]*[0-9.]+)?//; s/:[[:space:]]*,/: /}' "$pc"
    sudo sed -i -E '/^Requires(\.private)?:[[:space:]]*$/d' "$pc"
done
# help2man (run by many package builds to make man pages) imports Locale::gettext, whose compiled module was built for
# an older Perl than the image's and does not load; fall back to untranslated messages so help2man works
if [ -f "$STAGE/usr/bin/help2man" ]; then
    sudo sed -i 's|^use Locale::gettext qw(gettext);$|BEGIN { eval { require Locale::gettext; Locale::gettext->import(qw(gettext)); 1 } or eval q{ package Locale::gettext; sub domain { bless {}, shift } sub get { $_[1] } package main; sub gettext { $_[0] } 1 }; }|' "$STAGE/usr/bin/help2man"
fi
# what the image provides, recorded in get's database as base/NAME with its files: get does not rebuild what the
# base system already has, never overwrites base files by accident, and a port replaces its base package in place
sudo rm -rf "$STAGE/var/db/get/pkgs"/base__*
sudo "$BUILD_DIR/tools/live-image/base-packages.sh" "$ROOTFS" "$STAGE" "$STAGE/usr/share/systemlinux/base-packages" "$STAGE/var/db/get"
# every library that PID 1 and the core programs need must resolve inside the image
sudo "$BUILD_DIR/tools/live-image/check-libs.sh" "$STAGE" usr/bin/dinit usr/bin/dinitctl usr/bin/udevd usr/bin/udevadm \
    usr/bin/bash usr/bin/NetworkManager usr/bin/dbus-daemon usr/bin/agetty usr/bin/login usr/bin/mount usr/bin/ls \
    usr/bin/curl usr/bin/tar usr/bin/xz \
    usr/bin/make usr/bin/gcc usr/bin/g++ 'usr/libexec/gcc/*/*/cc1' 'usr/libexec/gcc/*/*/cc1plus' usr/bin/ld usr/bin/as \
    usr/bin/ar usr/bin/cmake usr/bin/ninja usr/bin/pkgconf usr/bin/perl usr/bin/python3 usr/bin/patch
echo "$IMAGE_VERSION" | sudo tee "$STAGE/usr/share/systemlinux/image-version" >/dev/null
sudo install -Dm644 "$KERNEL" "$STAGE/boot/vmlinuz"
# the kernel's whole module tree, so the running system (live and installed) can load NIC, GPU, sound... drivers
if [ -d "$MODULES_ROOT/lib/modules/$KVER" ]; then
    sudo mkdir -p "$STAGE/usr/lib/modules"
    sudo cp -a "$MODULES_ROOT/lib/modules/$KVER" "$STAGE/usr/lib/modules/"
    sudo depmod -b "$STAGE" "$KVER"   # $STAGE/lib -> usr/lib
fi
sudo mksquashfs "$STAGE" "$WORKSPACE/live/rootfs.squashfs" -comp zstd -Xcompression-level 6 -b 1M -noappend -no-xattrs
sudo rm -rf "$STAGE"
sudo chown "$USER" "$WORKSPACE/live/rootfs.squashfs"
ls -lh "$WORKSPACE/live/rootfs.squashfs"
BUILD_ID="$IMAGE_VERSION-$(date +%s)"
echo "$BUILD_ID" > "$WORKSPACE/live/build-id"
KVER=$KVER MODULES_ROOT=$MODULES_ROOT BUILD_ID=$BUILD_ID WORK=$HOME/.cache/systemlinux-initrd "$BUILD_DIR/tools/live-image/build-initrd.sh" "$WORKSPACE/live/initrd.img"

echo "=== [6/7] COPYING KERNEL AND WRITING grub.cfg ==="
install -m644 "$KERNEL" "$WORKSPACE/live/vmlinuz"
cat > "$WORKSPACE/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=3

# QEMU smoke test (tools/tests/boot-smoke.sh): a disk that carries a /SMOKETEST file picks the serial entry
# without anyone pressing a key. Real hardware never has that file, so nothing changes there. Only the first two disks
# are looked at: searching every device with BIOS disk calls kept GRUB on "Welcome to GRUB!" for half a minute.
if [ -f (hd0)/SMOKETEST -o -f (hd1)/SMOKETEST ]; then
    serial --unit=0 --speed=115200
    terminal_input serial
    terminal_output serial
    set default=serial
    set timeout=0
fi

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

menuentry "systemLinux $IMAGE_VERSION (serial console)" --id serial {
    if [ ! -f /live/vmlinuz ]; then
        search --no-floppy --set=root --file /live/vmlinuz
    fi
    linux /live/vmlinuz quiet loglevel=3 console=tty0 console=ttyS0,115200
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

echo "=== [7/7] MASTERING ISO AND PACKING PROFILES ==="
# profile-*.tar.xz (+ .sha256/.requires): upload them next to the ISO in the release; `get --profile NAME` installs them
ROOTFS=$ROOTFS "$BUILD_DIR/tools/profiles/profiles.sh" build "$PROFILES_OUT"
# ports.tar.xz (+ .sha256) is published with the release; `get --sync` downloads it
tar -cJf "$PROFILES_OUT/ports.tar.xz" --owner=0 --group=0 --sort=name ports
(cd "$PROFILES_OUT" && sha256sum ports.tar.xz > ports.tar.xz.sha256)
"$GRUB_MKRESCUE" -o "$ISO" "$WORKSPACE" -volid SYSTEMLINUX
sudo rm -rf "$WORKSPACE"
(cd "$(dirname "$ISO")" && sha256sum "$(basename "$ISO")" | tee "$(basename "$ISO").sha256")
echo "SUCCESS: $ISO"
