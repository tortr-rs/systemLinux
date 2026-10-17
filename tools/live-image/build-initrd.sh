#!/bin/bash
# Build the small live initramfs: busybox + cryptsetup (for LUKS-encrypted installs) + the init
# script. No firmware: the live image is kernel + installer only.
#
# busybox: BUSYBOX=PATH (build_iso.sh builds a static one inside the image, tools/busybox/build.sh), else the
# build host's. cryptsetup comes from the build host; copy-bin.sh copies it with the shared libraries and the
# loader it needs, at their host paths (glibc or musl alike).
#
# The distro kernels build most storage and filesystem drivers (isofs, squashfs, overlay, loop, usb, ahci, nvme...)
# as modules, so those modules (plus their dependencies) are copied from the kernel's module tree into the
# initramfs; init loads them before looking for the live medium.
#   KVER=...        kernel release the ISO embeds (default: the running kernel)
#   MODULES_ROOT=.. directory that holds lib/modules/KVER (default: / ; build_iso.sh sets it when it unpacks a kernel package)
#   ALLOW_NO_MODULES=1  do not fail when no modules can be copied (kernel with everything built in)
#   INITRD_MODULES  space separated module names to include (default list below)
#
# usage: WORK=~/.cache/systemlinux-initrd ./build-initrd.sh OUTPUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:?usage: build-initrd.sh OUTPUT}
WORK=${WORK:-$HOME/.cache/systemlinux-initrd}
rm -rf "$WORK/root" && mkdir -p "$WORK/root/bin" "$WORK/root/sbin" "$WORK/root/etc"

if [ -n "${BUSYBOX:-}" ]; then
    echo "== busybox: $BUSYBOX; cryptsetup from the build host"
    install -m755 "$BUSYBOX" "$WORK/root/bin/busybox"
    "$REPO/tools/overlay-common/copy-bin.sh" "$WORK/root" cryptsetup
else
    echo "== copying busybox and cryptsetup from the build host"
    "$REPO/tools/overlay-common/copy-bin.sh" "$WORK/root" busybox cryptsetup
    BB=$(readlink -f "$(command -v busybox)")
    [ -x "$WORK/root$BB" ] || { echo "ERROR: busybox not copied to initramfs" >&2; exit 1; }
    [ "$BB" = /bin/busybox ] || ln -sf "$BB" "$WORK/root/bin/busybox"
fi
CS=$(readlink -f "$(command -v cryptsetup)")
# copy-bin.sh keeps the host paths (e.g. /usr/sbin/cryptsetup); the init script expects /sbin/cryptsetup
[ -x "$WORK/root$CS" ] || { echo "ERROR: cryptsetup not copied to initramfs" >&2; exit 1; }
[ "$CS" = /sbin/cryptsetup ] || ln -sf "$CS" "$WORK/root/sbin/cryptsetup"

install -m755 "$HERE/init" "$WORK/root/init"
# BUILD_ID ties this initramfs to the ISO it is shipped in (the same id goes into /live/build-id on the ISO)
[ -n "${BUILD_ID:-}" ] && echo "$BUILD_ID" > "$WORK/root/build-id"
# A distro kernel without its storage/filesystem modules in the initramfs boots into "could not find the live medium".
# That used to be only a warning, so the broken ISO was still produced: fail the build unless the kernel has everything built in.
nomods() {
    if [ "${ALLOW_NO_MODULES:-0}" = 1 ]; then echo "WARNING: $1; the live ISO only boots if the kernel has storage/filesystem support built in" >&2
    else echo "ERROR: $1 (set ALLOW_NO_MODULES=1 only for a kernel with isofs/squashfs/overlay/loop and the storage drivers built in)" >&2; exit 1; fi
}
echo "== copying kernel modules for live-medium discovery"
KVER=${KVER:-$(uname -r)}
MODULES_ROOT=${MODULES_ROOT:-}
MODDIR=$MODULES_ROOT/lib/modules/$KVER
INITRD_MODULES=${INITRD_MODULES:-"isofs udf squashfs overlay loop sr_mod cdrom sd_mod usb_storage uas
    xhci_pci xhci_hcd ehci_pci ehci_hcd ohci_pci ohci_hcd uhci_hcd ahci libahci nvme nvme_core mmc_block
    virtio_blk virtio_scsi virtio_pci virtio virtio_ring scsi_mod scsi_common libata ata_piix ata_generic pata_acpi
    vmw_pvscsi mptspi mptsas BusLogic hv_storvsc hv_vmbus vfat fat exfat ext4 xfs btrfs f2fs nls_cp437 nls_ascii nls_utf8 dm_mod dm_crypt"}
# Whole driver directories (every ATA/SATA/PATA, SCSI, USB storage/host, NVMe, MMC and virtio-block driver): the medium may
# sit behind any controller (QEMU's default IDE CD-ROM needs ata_piix, VMware pvscsi, Hyper-V storvsc, ...).
# The init loads the ones matching the hardware by modalias. Test/dummy devices are excluded.
INITRD_MODDIRS=${INITRD_MODDIRS:-"kernel/drivers/ata/ kernel/drivers/scsi/ kernel/drivers/nvme/host/ kernel/drivers/mmc/host/
    kernel/drivers/usb/storage/ kernel/drivers/usb/host/ kernel/drivers/block/virtio_blk kernel/drivers/cdrom/
    kernel/drivers/virtio/ kernel/drivers/hv/"}
INITRD_EXCLUDE=${INITRD_EXCLUDE:-"scsi_debug null_blk brd ublk_drv zram"}
# Ubuntu's linux-modules packages ship no modules.dep (their postinst runs depmod): generate it in the unpacked tree
if [ -n "$MODULES_ROOT" ] && [ -d "$MODDIR" ] && [ ! -f "$MODDIR/modules.dep" ] && command -v depmod >/dev/null; then
    depmod -b "$MODULES_ROOT" "$KVER" || true
fi
if [ -f "$MODDIR/modules.dep" ] && command -v depmod >/dev/null; then
    DEST=$WORK/root/lib/modules/$KVER
    mkdir -p "$DEST"
    # modules.dep lines look like "kernel/fs/isofs/isofs.ko.zst: kernel/lib/zlib_inflate/..."; collect each wanted module and its deps
    wanted=$(awk -v mods="$INITRD_MODULES" -v dirs="$INITRD_MODDIRS" -v excl="$INITRD_EXCLUDE" '
        BEGIN { n = split(mods, a, /[ \t\n]+/); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1
                n = split(excl, a, /[ \t\n]+/); for (i = 1; i <= n; i++) if (a[i] != "") skip[a[i]] = 1
                nd = split(dirs, dl, /[ \t\n]+/) }
        { split($0, kv, ":"); f = kv[1]; b = f; sub(/.*\//, "", b); sub(/\.ko.*/, "", b)
          gsub(/-/, "_", b)
          if (!(b in want) && !(b in skip)) for (i = 1; i <= nd; i++) if (dl[i] != "" && index(f, dl[i]) == 1) want[b] = 1
          if ((b in want) && !(b in skip)) { print f; m = split(kv[2], d, " "); for (i = 1; i <= m; i++) print d[i] } }' "$MODDIR/modules.dep" | sort -u)
    count=0
    for f in $wanted; do
        src=$MODDIR/$f; [ -f "$src" ] || continue
        out=$DEST/${f%.ko*}.ko; mkdir -p "$(dirname "$out")"
        case "$src" in
            *.ko)     cp "$src" "$out" ;;
            *.ko.zst) zstd -dqc "$src" > "$out" ;;
            *.ko.xz)  xz -dc "$src" > "$out" ;;
            *.ko.gz)  gzip -dc "$src" > "$out" ;;
            *) continue ;;
        esac
        count=$((count + 1))
    done
    cp "$MODDIR"/modules.{order,builtin,builtin.modinfo} "$DEST/" 2>/dev/null || true
    depmod -b "$WORK/root" "$KVER"
    echo "   $count kernel modules for $KVER"
    [ "$count" -gt 0 ] || nomods "no kernel modules copied"
else
    nomods "no module tree (modules.dep/depmod) for kernel $KVER under ${MODULES_ROOT:-/}"
fi

"$WORK/root/bin/busybox" --list 2>/dev/null | grep -x modprobe >/dev/null || echo "WARNING: busybox has no modprobe applet; kernel modules cannot be loaded" >&2
mkdir -p "$WORK/root"/{proc,sys,dev,mnt,newroot,overlay}
# zstd-compressed (the kernel unpacks it): uncompressed it is ~60 MB, which GRUB reads very slowly through BIOS disk calls
( cd "$WORK/root" && find . | sort | cpio -o -H newc -R 0:0 --quiet ) | zstd -q -19 -T0 > "$OUT"
ls -lh "$OUT"
