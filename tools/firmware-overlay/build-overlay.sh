#!/bin/bash
# Build the firmware overlay from Debian's firmware packages (Wi-Fi, Bluetooth, graphics, sound,
# NIC firmware). The full kernel has its drivers built in, and they read firmware from the initrd.
# Files are xz-compressed (--check=crc32, as the kernel requires) to keep the RAM-disk small.
# Needs a Debian host with apt; no root.
# Output: $WORK/ov5/usr/lib/firmware
# usage: WORK=~/.cache/systemlinux-firmware ./build-overlay.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export WORK=${WORK:-$HOME/.cache/systemlinux-firmware}
rm -rf "$WORK/stage" "$WORK/ov5"
mkdir -p "$WORK/debs" "$WORK/stage" "$WORK/ov5/usr/lib"
cd "$WORK"

echo "== downloading firmware packages"
for p in $(cat "$HERE/firmware.txt"); do
    c=$(apt-cache policy "$p" 2>/dev/null | sed -n 's/^  Candidate: //p')
    if [ -n "$c" ] && [ "$c" != "(none)" ]; then
        (cd debs && apt-get download "$p" >/dev/null 2>&1) || echo "warning: could not download $p"
    fi
done
for deb in debs/*.deb; do dpkg-deb -x "$deb" stage; done

echo "== compressing firmware"
python3 - <<'PY'
import os, subprocess
src = os.environ['WORK'] + '/stage/usr/lib/firmware'
dst = os.environ['WORK'] + '/ov5/usr/lib/firmware'
n = 0
for dp, dns, fns in os.walk(src):
    rel = os.path.relpath(dp, src)
    os.makedirs(os.path.join(dst, rel), exist_ok=True)
    for f in fns:
        s = os.path.join(dp, f)
        d = os.path.join(dst, rel, f)
        if f.endswith(('.xz', '.zst')):
            if os.path.islink(s): os.symlink(os.readlink(s), d)
            else: os.link(s, d)
        elif os.path.islink(s):
            os.symlink(os.readlink(s) + '.xz', d + '.xz')
        else:
            with open(d + '.xz', 'wb') as out:
                subprocess.run(['xz', '-9e', '--check=crc32', '--lzma2=dict=1MiB', '-c', s], stdout=out, check=True)
            n += 1
print(n, 'firmware files compressed')
PY
find "$WORK/ov5" -xtype l -delete
chmod -R go-w "$WORK/ov5"
du -sh "$WORK/ov5/usr/lib/firmware"
echo "overlay ready: $WORK/ov5"
