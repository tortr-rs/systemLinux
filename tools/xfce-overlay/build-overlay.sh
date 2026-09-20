#!/bin/bash
# Build the live-XFCE overlay from Debian packages (needs a Debian/Ubuntu host with apt, no root).
# Output: $WORK/ov3 (Debian files that do not already exist in the Gentoo rootfs) and
#         $WORK/ov4 (live session launcher + /etc/systemL/services.conf).
# usage: WORK=~/.cache/systemlinux-xfce ROOTFS=/path/to/rootfs ./build-overlay.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export WORK=${WORK:-$HOME/.cache/systemlinux-xfce}
export ROOTFS=${ROOTFS:-$HERE/../../rootfs}
mkdir -p "$WORK/debs"; cd "$WORK"

session_files() {
    echo "== live session files, installer, Firefox policy, loadkeys wrapper"
    rm -rf ov4 && mkdir -p ov4/usr/local/bin ov4/etc/systemL
    install -m755 "$HERE/start-xfce" ov4/usr/local/bin/start-xfce
    printf '# started and supervised by systemL: <name> <command> [args...]\nxfce /usr/local/bin/start-xfce\n' > ov4/etc/systemL/services.conf
    cp -a "$HERE/extras/." ov4/
    chmod -R go-w ov4
}
if [ "${1:-}" = "--session-only" ]; then session_files; exit 0; fi

echo "== resolving package closure"
apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
    $(cat "$HERE/packages.txt") 2>/dev/null | grep -E '^[a-z0-9]' | grep -v ':' | sort -u \
    | grep -v -x -F -f "$HERE/blocklist.txt" > wanted.txt
: > pkgs.txt
for p in $(cat wanted.txt); do
    c=$(apt-cache policy "$p" 2>/dev/null | sed -n 's/^  Candidate: //p')
    [ -n "$c" ] && [ "$c" != "(none)" ] && echo "$p" >> pkgs.txt
done
echo "$(wc -l < pkgs.txt) packages"

echo "== downloading"
(cd debs && xargs -n 60 apt-get download < ../pkgs.txt >/dev/null)
rm -f debs/*_i386.deb

echo "== merging into overlay"
python3 "$HERE/merge.py"
"$HERE/post.sh"
python3 "$HERE/checklibs.py" | tail -3

session_files
chmod -R go-w ov3
echo "overlay ready: $WORK/ov3 $WORK/ov4"
