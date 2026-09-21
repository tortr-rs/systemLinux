#!/bin/bash
# Prepare an image update for publishing: hashes the three image files, writes latest.json and signs it.
# Upload OUTDIR/* to the GitHub release v<VERSION> (assets: vmlinuz, initrd.img, rootfs.squashfs,
# latest.json, latest.json.sig). `goget upgrade` on installed systems then finds it through
# https://github.com/tortr-rs/systemLinux/releases/latest/download/latest.json
#
# usage: tools/publish-image.sh VERSION VMLINUZ INITRD SQUASHFS OUTDIR [NOTES]
# The signing key is ~/.config/systemlinux-update/update.key (create it once with `imagesign keygen`).
set -euo pipefail
VERSION=$1 VMLINUZ=$2 INITRD=$3 SQUASHFS=$4 OUT=$5 NOTES=${6:-}
HERE=$(cd "$(dirname "$0")" && pwd)
KEY=${UPDATE_KEY:-$HOME/.config/systemlinux-update/update.key}
BASE=${BASE_URL:-https://github.com/tortr-rs/systemLinux/releases/download/v$VERSION}
[ -f "$KEY" ] || { echo "signing key $KEY not found"; exit 1; }
SIGN=$(mktemp -d)/imagesign
(cd "$HERE/imagesign" && CGO_ENABLED=0 go build -o "$SIGN" .)
mkdir -p "$OUT"
cp "$VMLINUZ" "$OUT/vmlinuz"; cp "$INITRD" "$OUT/initrd.img"; cp "$SQUASHFS" "$OUT/rootfs.squashfs"
python3 - "$VERSION" "$BASE" "$OUT" "$NOTES" <<'PY'
import hashlib, json, os, sys, datetime
version, base, out, notes = sys.argv[1:5]
files = []
for name in ('vmlinuz', 'initrd.img', 'rootfs.squashfs'):
    p = os.path.join(out, name)
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    files.append({'name': name, 'url': f'{base}/{name}', 'sha256': h.hexdigest(), 'size': os.path.getsize(p)})
idx = {'version': version, 'released': datetime.date.today().isoformat(), 'notes': notes, 'files': files}
open(os.path.join(out, 'latest.json'), 'w').write(json.dumps(idx, indent=2) + '\n')
PY
"$SIGN" sign "$KEY" "$OUT/latest.json" > "$OUT/latest.json.sig"
"$SIGN" verify "$(cat "$HERE/../goget/upgrade.go" | sed -n 's/.*updatePublicKeyHex = "\(.*\)".*/\1/p')" "$OUT/latest.json" "$OUT/latest.json.sig"
ls -la "$OUT"
