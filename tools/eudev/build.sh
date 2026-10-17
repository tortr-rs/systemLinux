#!/bin/sh
# Build eudev (the udev device manager without systemd) from a pinned release tarball inside the image
# (chroot-run.sh) and install it there: /usr/bin/udevd, /usr/bin/udevadm, libudev.so.1, the udev helpers
# (ata_id, scsi_id, ...), rules and hwdb. It replaces systemd-udevd and systemd's libudev.
# usage: build.sh ROOTFS   (as root)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); C=$HERE/../overlay-common
ROOT=${1:?usage: build.sh ROOTFS}
EUDEV_VERSION=3.2.14
EUDEV_SHA256=8da4319102f24abbf7fff5ce9c416af848df163b29590e666d334cc1927f006f
B=/var/tmp/eudev-build
rm -rf "$ROOT$B"; mkdir -p "$ROOT$B"; trap 'rm -rf "$ROOT$B"' EXIT
"$C/fetch.sh" "https://github.com/eudev-project/eudev/releases/download/v$EUDEV_VERSION/eudev-$EUDEV_VERSION.tar.gz" "$EUDEV_SHA256" "$ROOT$B/src.tar.gz"
tar --no-same-owner -xzf "$ROOT$B/src.tar.gz" -C "$ROOT$B" --strip-components=1
"$C/chroot-run.sh" "$ROOT" "cd $B
./configure -q --prefix=/usr --sysconfdir=/etc --bindir=/usr/bin --sbindir=/usr/bin --libdir=/usr/lib64 \
    --with-rootprefix=/usr --with-rootlibdir=/usr/lib64 --with-rootlibexecdir=/usr/lib/udev \
    --enable-kmod --enable-blkid --enable-hwdb --disable-manpages --disable-selinux --disable-static
make -j\$JOBS
# systemd's libudev.so.1.7.x would otherwise stay next to eudev's and keep the libudev.so.1 symlink
rm -f /usr/lib64/libudev.so*
make install
rm -f /usr/lib64/libudev.la
# the dinit service and older scripts call it as /usr/lib/udev/udevd
ln -sf ../../bin/udevd /usr/lib/udev/udevd
# eudev's hwdb plus the hwdb.d files other packages installed
udevadm hwdb --update"
