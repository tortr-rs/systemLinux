#!/bin/bash
# Build the base services overlay from nixpkgs, via goget itself: Bluetooth, audio, time sync,
# power profiles, printing, firmware updates, Flatpak, a default firewall, locales and input
# methods -- everyday daemons, no desktop, no host package manager involved at all.
# Output: $WORK/ov3 (the fetched packages' own /nix tree) and $WORK/ov4 (session files: services.conf,
# wrapper scripts, configs -- see session/).
# usage: WORK=~/.cache/systemlinux-base ROOTFS=/path/to/rootfs ./build-overlay.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
GOGET=$REPO/goget/goget
WORK=${WORK:-$HOME/.cache/systemlinux-base}
# nix store directories are read-only, so stale content from a previous run (in nix-tmp, and in
# ov3 which it gets copied into below) needs write permission restored before rm -rf can clear it
chmod -R u+w "$WORK/nix-tmp" "$WORK/ov3" 2>/dev/null || true
rm -rf "$WORK/nix-tmp" "$WORK/ov3" "$WORK/ov4"
mkdir -p "$WORK"

echo "== fetching base daemons from nixpkgs"
# fcitx5 only, not ibus: ibus's prebuilt closure drags in a GTK+Python setup GUI (~300+ MB)
# that can never run on a console-only system with no desktop session anyway. fcitx5 (a leaner,
# GUI-toolkit-free C++ input framework) covers the same "CJK input methods" need on its own.
"$GOGET" install --root "$WORK/nix-tmp" --system -y \
    bluez chrony power-profiles-daemon pipewire wireplumber cups fwupd flatpak nftables \
    glibc-locales fcitx5 noto-fonts-cjk-sans elogind polkit

echo "== packaging the /nix tree into ov3"
mkdir -p "$WORK/ov3/nix"
cp -a "$WORK/nix-tmp/nix/." "$WORK/ov3/nix/"
# Strip docs/man pages/translated strings/build-time headers: nothing a console system needs at
# runtime, and this closure (15 packages, 387 store paths) is otherwise big enough to blow past
# GitHub's 2 GiB release-asset limit -- the same problem and the same fix the old GNOME-edition
# build script used for exactly this reason. glibc-locales' own lib/locale/locale-archive (the
# actual runtime locale data /etc/profile.d/locale.sh points at) is untouched -- only share/locale
# (translated UI strings for these packages' own messages, not needed while the project is
# English-only) goes.
chmod -R u+w "$WORK/ov3/nix/store"
find "$WORK/ov3/nix/store" -mindepth 2 -maxdepth 3 \
    \( -path '*/share/man' -o -path '*/share/doc' -o -path '*/share/info' \
       -o -path '*/share/locale' -o -path '*/share/gtk-doc' -o -path '*/include' \) \
    -prune -exec rm -rf {} +
chmod -R go-w "$WORK/ov3"

echo "== session files (services.conf, wrapper scripts, configs)"
rm -rf "$WORK/ov4" && mkdir -p "$WORK/ov4"
cp -a "$HERE/session/." "$WORK/ov4/"
chmod -R go-w "$WORK/ov4"

echo "overlay ready: $WORK/ov3 $WORK/ov4"
