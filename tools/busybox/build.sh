#!/bin/sh
# Build a static busybox for the initramfs inside the image (chroot-run.sh), so the ISO build does not depend on
# the host having one (or on it being static). The binary is copied out to OUT; nothing is installed in the image.
# usage: build.sh ROOTFS OUT   (as root)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); C=$HERE/../overlay-common
ROOT=${1:?usage: build.sh ROOTFS OUT} OUT=${2:?usage: build.sh ROOTFS OUT}
BB_VERSION=1.38.0
BB_SHA256=34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2
B=/var/tmp/busybox-build
rm -rf "$ROOT$B"; mkdir -p "$ROOT$B"; trap 'rm -rf "$ROOT$B"' EXIT
"$C/fetch.sh" "https://busybox.net/downloads/busybox-$BB_VERSION.tar.bz2" "$BB_SHA256" "$ROOT$B/src.tar.bz2"
tar --no-same-owner -xjf "$ROOT$B/src.tar.bz2" -C "$ROOT$B" --strip-components=1
"$C/chroot-run.sh" "$ROOT" "cd $B
make -s defconfig
# static; tc does not build against current kernel headers (CBQ was removed from Linux)
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
make -s oldconfig </dev/null >/dev/null
make -s -j\$JOBS busybox"
install -m755 "$ROOT$B/busybox" "$OUT"
