#!/bin/bash
# Build the small live initramfs: busybox + the init script (+ the firmware overlay, so built-in
# drivers can load firmware while the kernel initialises, before the real root is mounted).
# usage: WORK=~/.cache/systemlinux-initrd FW_CPIO=/path/ov5.cpio ./build-initrd.sh OUTPUT
# Needs a Debian host with apt (busybox-static); no root.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build-initrd.sh OUTPUT}
WORK=${WORK:-$HOME/.cache/systemlinux-initrd}
rm -rf "$WORK/root" && mkdir -p "$WORK/debs" "$WORK/root/bin" "$WORK/root/sbin" "$WORK/root/etc"
(cd "$WORK/debs" && apt-get download busybox-static >/dev/null)
dpkg-deb -x "$WORK"/debs/busybox-static_*.deb "$WORK/x"
install -m755 "$WORK/x/usr/bin/busybox" "$WORK/root/bin/busybox"
install -m755 "$HERE/init" "$WORK/root/init"
# BUILD_ID ties this initramfs to the ISO it is shipped in (the same id goes into /live/build-id on the ISO)
[ -n "${BUILD_ID:-}" ] && echo "$BUILD_ID" > "$WORK/root/build-id"
mkdir -p "$WORK/root"/{proc,sys,dev,mnt,newroot,overlay}
( cd "$WORK/root" && find . | sort | cpio -o -H newc -R 0:0 --quiet ) > "$OUT"
if [ -n "${FW_CPIO:-}" ]; then cat "$FW_CPIO" >> "$OUT"; fi
ls -lh "$OUT"
