#!/bin/sh
# Build sudo from a pinned release tarball INSIDE the image (chroot, with the image's own compiler and libraries:
# PAM, glibc) and install it there. Replaces the old /usr/bin/sudo stub, which only ran the command as the caller.
# usage: build.sh ROOTFS   (as root)
set -eu
ROOT=${1:?usage: build.sh ROOTFS}
SUDO_VERSION=1.9.17p2
SUDO_SHA256=4a38a1ab3adb1199257edc2a7c4a2bd714665eb605b04368843b06dada2cfcfb
HERE=$(cd "$(dirname "$0")" && pwd); C=$HERE/../overlay-common
B=/var/tmp/sudo-build
rm -rf "$ROOT$B"; mkdir -p "$ROOT$B"; trap 'rm -rf "$ROOT$B"' EXIT
"$C/fetch.sh" "https://www.sudo.ws/dist/sudo-$SUDO_VERSION.tar.gz" "$SUDO_SHA256" "$ROOT$B/sudo.tar.gz"
tar --no-same-owner -xzf "$ROOT$B/sudo.tar.gz" -C "$ROOT$B" --strip-components=1
rm -f "$ROOT/usr/bin/sudo"
"$C/chroot-run.sh" "$ROOT" "cd $B
./configure -q --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/lib \
    --with-pam --with-env-editor --without-sendmail --with-rundir=/run/sudo --with-vardir=/var/db/sudo \
    --enable-tmpfiles.d=no --disable-nls
make -j\$JOBS
make install"
mkdir -p "$ROOT/etc/pam.d"
cat > "$ROOT/etc/pam.d/sudo" <<'PAM'
auth		include		system-auth
account		include		system-auth
password	include		system-auth
session		include		system-auth
PAM
# the stub's leftovers: the sudoers.d entry for root is already in the default /etc/sudoers
rm -f "$ROOT/etc/sudoers.d/systemlinux"
"$C/chroot-run.sh" "$ROOT" "visudo -c"
