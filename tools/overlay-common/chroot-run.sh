#!/bin/sh
# Run a shell command inside an image tree, with the image's own compiler and libraries. Everything the ISO build
# compiles goes through here, so the build works the same on any host distro (glibc or musl, any compiler):
# the host only downloads, unpacks and packs.
# /dev and /sys are bind-mounted as rslave: the host's are shared mounts, and unmounting a shared copy would
# unmount the host's own /dev/pts. Run as root.
# usage: chroot-run.sh ROOT 'COMMAND'
set -eu
ROOT=${1:?usage: chroot-run.sh ROOT COMMAND}; shift
mkdir -p "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/tmp" "$ROOT/var/tmp"
chmod 1777 "$ROOT/tmp" "$ROOT/var/tmp"
cleanup() {
    umount -lR "$ROOT/dev" 2>/dev/null || true
    umount -lR "$ROOT/sys" 2>/dev/null || true
    umount "$ROOT/proc" 2>/dev/null || true
}
trap cleanup EXIT
mount --rbind /dev "$ROOT/dev"; mount --make-rslave "$ROOT/dev"
mount --rbind /sys "$ROOT/sys"; mount --make-rslave "$ROOT/sys"
mount -t proc proc "$ROOT/proc"
chroot "$ROOT" /usr/bin/env -i HOME=/root TERM=dumb LANG=C.UTF-8 \
    PATH=/usr/bin:/usr/sbin:/usr/x86_64-pc-linux-gnu/bin JOBS="$(nproc)" /bin/sh -ec "$*"
