#!/bin/bash
# Build the firmware overlay from nixpkgs (linux-firmware, sof-firmware), via goget itself. The
# full kernel has its drivers built in, and they read firmware from the initrd.
# Files are xz-compressed (--check=crc32, as the kernel requires) to keep the RAM-disk small.
# Output: $WORK/ov5/usr/lib/firmware
# usage: WORK=~/.cache/systemlinux-firmware ./build-overlay.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
GOGET=$REPO/goget/goget
export WORK=${WORK:-$HOME/.cache/systemlinux-firmware}
# nix store directories are read-only, so stale content from a previous run (in nix-tmp, and in
# ov5, some of which is hardlinked straight from the nix store and so shares its read-only bits)
# needs write permission restored before rm -rf can clear it
chmod -R u+w "$WORK/nix-tmp" "$WORK/ov5" 2>/dev/null || true
rm -rf "$WORK/nix-tmp" "$WORK/ov5"
mkdir -p "$WORK/ov5/usr/lib"
cd "$WORK"

echo "== fetching firmware from nixpkgs"
"$GOGET" install --root "$WORK/nix-tmp" --system -y linux-firmware sof-firmware

echo "== compressing firmware"
WORK="$WORK" python3 - <<'PY'
import os, subprocess, glob
work = os.environ['WORK']
dst = work + '/ov5/usr/lib/firmware'
n = 0
for pkg_glob in ('linux-firmware-*', 'sof-firmware-*'):
    stores = glob.glob(work + '/nix-tmp/nix/store/*-' + pkg_glob)
    if not stores:
        continue
    src = stores[0] + '/lib/firmware'
    if not os.path.isdir(src):
        continue
    for dp, dns, fns in os.walk(src):
        rel = os.path.relpath(dp, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in fns:
            s = os.path.join(dp, f)
            d = os.path.join(dst, rel, f)
            if os.path.exists(d) or os.path.islink(d):
                continue  # sof-firmware after linux-firmware: don't overwrite already-compressed files
            if f.endswith(('.xz', '.zst')):
                if os.path.islink(s): os.symlink(os.readlink(s), d)
                else: os.link(s, d)
            elif os.path.islink(s):
                target = os.readlink(s)
                if not target.endswith('.xz'):
                    target += '.xz'
                os.symlink(target, d + '.xz')
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
