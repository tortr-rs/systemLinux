#!/bin/bash
# Build the small live initramfs: busybox + cryptsetup (for LUKS-encrypted installs) + the init
# script (+ the firmware overlay, so built-in drivers can load firmware while the kernel
# initialises, before the real root is mounted).
#
# busybox and cryptsetup come from nixpkgs via goget, not a host package manager: goget resolves
# their full runtime dependency closure (glibc and friends) the same way it does for an installed
# system, and that whole /nix/store subtree is copied into the initramfs verbatim so the copied
# binaries' hardcoded /nix/store ELF interpreter paths resolve at boot. This is why the initramfs
# is noticeably bigger than a single static busybox binary would be -- it is carrying a small
# glibc closure instead. /bin/busybox and /sbin/cryptsetup are plain symlinks into that tree so
# the init script does not need to know the exact store paths (those change on every nixpkgs
# update); it locates cryptsetup at runtime with `find /nix/store -maxdepth 2` instead.
#
# usage: WORK=~/.cache/systemlinux-initrd FW_CPIO=/path/ov5.cpio ./build-initrd.sh OUTPUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
GOGET=$REPO/goget/goget
OUT=${1:?usage: build-initrd.sh OUTPUT}
WORK=${WORK:-$HOME/.cache/systemlinux-initrd}
# nix store directories are read-only, so stale content from a previous run (in nix-tmp, and in
# root/nix which it gets copied into below) needs write permission restored before rm -rf can
# clear it -- otherwise the next run's cp -a fails trying to overwrite read-only leftovers.
chmod -R u+w "$WORK/nix-tmp" "$WORK/root" 2>/dev/null || true
rm -rf "$WORK/nix-tmp" "$WORK/root" && mkdir -p "$WORK/root/bin" "$WORK/root/sbin" "$WORK/root/etc"

echo "== fetching busybox and cryptsetup from nixpkgs"
"$GOGET" install --root "$WORK/nix-tmp" --system -y busybox cryptsetup
BB=$(readlink "$WORK/nix-tmp/nix/var/goget/profiles/system/current/bin/busybox")
CS=$(readlink "$WORK/nix-tmp/nix/var/goget/profiles/system/current/bin/cryptsetup")
mkdir -p "$WORK/root/nix"
cp -a "$WORK/nix-tmp/nix/." "$WORK/root/nix/"
ln -sf "$BB" "$WORK/root/bin/busybox"
ln -sf "$CS" "$WORK/root/sbin/cryptsetup"

install -m755 "$HERE/init" "$WORK/root/init"
# BUILD_ID ties this initramfs to the ISO it is shipped in (the same id goes into /live/build-id on the ISO)
[ -n "${BUILD_ID:-}" ] && echo "$BUILD_ID" > "$WORK/root/build-id"
mkdir -p "$WORK/root"/{proc,sys,dev,mnt,newroot,overlay}
( cd "$WORK/root" && find . | sort | cpio -o -H newc -R 0:0 --quiet ) > "$OUT"
if [ -n "${FW_CPIO:-}" ]; then cat "$FW_CPIO" >> "$OUT"; fi
ls -lh "$OUT"
