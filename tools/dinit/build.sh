#!/bin/sh
# Build dinit (PID 1) from a pinned release tarball inside the image (chroot-run.sh) and install it there.
# /sbin and /bin are both /usr/bin in the image, so the programs (dinit, dinitctl, dinit-check, and
# shutdown/reboot/poweroff/halt/soft-reboot) all go to /usr/bin.
# usage: build.sh ROOTFS   (as root)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); C=$HERE/../overlay-common
ROOT=${1:?usage: build.sh ROOTFS}
DINIT_VERSION=0.20.0
DINIT_SHA256=cd75b572a2eab4a9bd0610a2bb8cc154da7e80074e61cb1059a996dfd977baae
B=/var/tmp/dinit-build
rm -rf "$ROOT$B"; mkdir -p "$ROOT$B"; trap 'rm -rf "$ROOT$B"' EXIT
"$C/fetch.sh" "https://github.com/davmac314/dinit/archive/refs/tags/v$DINIT_VERSION.tar.gz" "$DINIT_SHA256" "$ROOT$B/src.tar.gz"
tar --no-same-owner -xzf "$ROOT$B/src.tar.gz" -C "$ROOT$B" --strip-components=1
"$C/chroot-run.sh" "$ROOT" "cd $B
./configure -q --prefix=/usr --sbindir=/usr/bin --syscontrolsocket=/run/dinitctl
make -j\$JOBS
# no stale reboot/poweroff symlinks in the way of make install
for n in reboot poweroff halt shutdown soft-reboot; do rm -f /usr/bin/\$n; done
make install"
