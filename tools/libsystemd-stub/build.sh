#!/bin/sh
# Build the libsystemd.so.0 stub (sd-stub.c, no systemd code) inside the image (chroot-run.sh) and install it to
# /usr/lib64, replacing systemd's library. Fails if any program in the image needs an sd_* symbol the stub does
# not export.
# usage: build.sh ROOTFS   (as root)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); C=$HERE/../overlay-common
ROOT=${1:?usage: build.sh ROOTFS}
B=/var/tmp/sdstub-build
rm -rf "$ROOT$B"; mkdir -p "$ROOT$B"; trap 'rm -rf "$ROOT$B"' EXIT
cp "$HERE/sd-stub.c" "$HERE/libsystemd.sym" "$ROOT$B/"
"$C/chroot-run.sh" "$ROOT" "cd $B
cc -O2 -fPIC -fvisibility=hidden -shared -Wall -Wextra -Werror \
    -Wl,--version-script=libsystemd.sym -Wl,-soname,libsystemd.so.0 -o libsystemd.so.0 sd-stub.c
L=/usr/lib64
rm -f \$L/libsystemd.so \$L/libsystemd.so.0 \$L/libsystemd.so.0.* \$L/pkgconfig/libsystemd.pc
install -m755 libsystemd.so.0 \$L/libsystemd.so.0
# every sd_*@VERSION the image's programs import must be exported by the stub
nm -D --defined-only \$L/libsystemd.so.0 | awk '{sub(/@@/, \"@\", \$3); print \$3}' | sort -u > have
find /usr -xdev -type f \\( -name '*.so*' -o -perm -u+x \\) 2>/dev/null | while read -r f; do
    readelf -d \"\$f\" 2>/dev/null | grep -q 'NEEDED.*\\[libsystemd\\.so\\.0\\]' || continue
    nm -D --undefined-only \"\$f\" 2>/dev/null | awk '\$2 ~ /^sd_/ {print \$2}'
done | sort -u > need
missing=\$(comm -23 need have)
[ -z \"\$missing\" ] || { echo \"libsystemd-stub: symbols used by the image but not provided:\" \$missing >&2; exit 1; }
echo \"libsystemd-stub: installed (\$(wc -l < need) imported symbols covered)\""
