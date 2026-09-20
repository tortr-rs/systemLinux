#!/bin/bash
# Build the "full" systemLinux kernel: the same Linux 7.2.6 with drivers for almost everything
# built in (monolithic). Applies extra-config.txt to kernel_7.2.6.config, converts any leftover
# modules to built-in, builds bzImage in the kernel source tree and saves the result.
#
# usage: [WORK=~/.cache/systemlinux-kernel] [TARBALL=.../linux-7.2.6.tar.xz] ./build-kernel.sh
# output: $OUT (default: ./vmlinuz-7.2.6-full) and ../../kernel_7.2.6-full.config
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
WORK=${WORK:-$HOME/.cache/systemlinux-kernel}
TARBALL=${TARBALL:-$REPO/systemlinux-distro/linux-7.2.6.tar.xz}
KSRC=${KSRC:-$WORK/linux-7.2.6}
OUT=${OUT:-$HERE/vmlinuz-7.2.6-full}
# systemlinux-distro/linux-7.2.6 only holds old build output, so build from the pristine tarball
if [ ! -f "$KSRC/Makefile" ]; then
    mkdir -p "$WORK"
    tar -xf "$TARBALL" -C "$WORK"
fi
cd "$KSRC"

cp "$REPO/kernel_7.2.6.config" .config
for o in $(grep -v '^#' "$HERE/extra-config.txt" | grep -v '^$' | sort -u); do
    scripts/config --file .config --enable "$o"
done
scripts/config --file .config --set-str LOCALVERSION "-full"
# Built-in drivers with missing firmware must fail fast: the sysfs fallback makes the kernel
# wait up to 60 seconds per missing file for a userspace helper that never answers.
for o in FW_LOADER_USER_HELPER FW_LOADER_USER_HELPER_FALLBACK DELL_RBU; do
    scripts/config --file .config --disable "$o"
done
make olddefconfig
echo "modules after olddefconfig: $(grep -c '=m$' .config)"
sed -i 's/=m$/=y/' .config      # no module loading in the live initrd: build everything in
make olddefconfig
make -j"$(nproc)" bzImage
cp .config "$REPO/kernel_7.2.6-full.config"
cp arch/x86/boot/bzImage "$OUT"
ls -la "$OUT"
echo "built: $OUT ($(make -s kernelrelease))"
