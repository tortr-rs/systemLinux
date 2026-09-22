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
rm -rf "$WORK/nix-tmp" "$WORK/ov3" "$WORK/ov4"
mkdir -p "$WORK"

echo "== fetching base daemons from nixpkgs"
"$GOGET" install --root "$WORK/nix-tmp" --system -y \
    bluez chrony power-profiles-daemon pipewire wireplumber cups fwupd flatpak nftables \
    glibc-locales ibus fcitx5 noto-fonts-cjk-sans elogind polkit

echo "== packaging the /nix tree into ov3"
mkdir -p "$WORK/ov3/nix"
cp -a "$WORK/nix-tmp/nix/." "$WORK/ov3/nix/"
chmod -R go-w "$WORK/ov3"

echo "== session files (services.conf, wrapper scripts, configs)"
rm -rf "$WORK/ov4" && mkdir -p "$WORK/ov4"
cp -a "$HERE/session/." "$WORK/ov4/"
chmod -R go-w "$WORK/ov4"

echo "overlay ready: $WORK/ov3 $WORK/ov4"
