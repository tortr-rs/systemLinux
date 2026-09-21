#!/bin/bash
# Build the GNOME live overlay from Debian packages (needs a Debian host with apt; no root).
# Reuses the merge/post/check scripts of tools/overlay-common. Debian's GTK/GNOME libraries take
# precedence over the base's (see LIB_OVERRIDE in merge.py); the base system's own daemons keep theirs.
# Output: $WORK/ov3 (Debian files not already in the rootfs) and $WORK/ov4 (session files).
# usage: WORK=~/.cache/systemlinux-gnome ROOTFS=/path/to/rootfs ./build-overlay.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
X=$HERE/../overlay-common
export WORK=${WORK:-$HOME/.cache/systemlinux-gnome}
export ROOTFS=${ROOTFS:-$HERE/../../rootfs}
export LIB_OVERRIDE=1
mkdir -p "$WORK/debs"; cd "$WORK"

session_files() {
    echo "== GNOME session files, installer, Firefox policy"
    rm -rf ov4 && mkdir -p ov4
    cp -a "$HERE/session/." ov4/
    chmod -R go-w ov4
}
if [ "${1:-}" = "--session-only" ]; then session_files; exit 0; fi

echo "== resolving package closure"
cat "$X/blocklist.txt" "$HERE/blocklist.extra.txt" | sort -u > blocklist.txt
apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    $(tr ' ' '\n' < "$HERE/packages.txt" | grep -v '^$') 2>/dev/null | grep -E '^[a-z0-9]' | grep -v ':' | sort -u \
    | grep -v -x -F -f blocklist.txt > wanted.txt
: > pkgs.txt
for p in $(cat wanted.txt); do
    c=$(apt-cache policy "$p" 2>/dev/null | sed -n 's/^  Candidate: //p')
    [ -n "$c" ] && [ "$c" != "(none)" ] && echo "$p" >> pkgs.txt
done
grep -v "^#" "$HERE/packages-nodeps.txt" | while read -r p; do [ -n "$p" ] && grep -qx "$p" pkgs.txt || echo "$p" >> pkgs.txt; done
echo "$(wc -l < pkgs.txt) packages"
# only the packages of the current list may be merged (older downloads stay in debs/ otherwise)
for f in debs/*.deb; do n=${f##*/}; n=${n%%_*}; grep -qx "$n" pkgs.txt || rm -f "$f"; done

echo "== downloading"
(cd debs && xargs -n 60 apt-get download < ../pkgs.txt >/dev/null)
rm -f debs/*_i386.deb

echo "== merging into overlay"
python3 "$X/merge.py"
mkdir -p ov3/usr/share/glib-2.0/schemas && cp "$HERE"/schemas/* ov3/usr/share/glib-2.0/schemas/   # gsettings defaults, compiled by post.sh
"$X/post.sh"
python3 "$X/checklibs.py" | tail -12
session_files
chmod -R go-w ov3
echo "overlay ready: $WORK/ov3 $WORK/ov4"
