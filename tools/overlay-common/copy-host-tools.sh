#!/bin/sh
# Put a few of the build host's programs (GRUB, efibootmgr, mkfs.fat: the installer's boot tools, which the base
# system does not have) into an image WITHOUT mixing the host's libraries into the image's own.
#
# Each program and every library it needs (the host's glibc and loader included) go to /usr/lib/systemlinux-host/;
# /usr/bin/NAME becomes a small launcher that starts the program with the host's loader and only those libraries.
# The image's /usr/lib and /usr/lib64 are not touched, so nothing else ever loads a host library.
# usage: copy-host-tools.sh DEST PROGRAM...
set -eu
DEST=${1:?usage: copy-host-tools.sh DEST PROGRAM...}; shift
H=/usr/lib/systemlinux-host
mkdir -p "$DEST$H/bin" "$DEST$H/lib" "$DEST/usr/bin"
for p in "$@"; do
    path=$(command -v "$p" 2>/dev/null || true)
    [ -n "$path" ] || { echo "copy-host-tools: $p not found on the build host" >&2; exit 1; }
    path=$(readlink -f "$path")
    name=${p##*/}
    # a script (grub-reboot, grub-set-default) needs no libraries: copy it as it is
    if [ "$(head -c 4 "$path")" != "$(printf '\177ELF')" ]; then
        install -m755 "$path" "$DEST/usr/bin/$name"; continue
    fi
    if ldd "$path" 2>/dev/null | grep -q 'not found'; then echo "copy-host-tools: missing libraries for $path" >&2; exit 1; fi
    cp -L "$path" "$DEST$H/bin/$name"
    # its libraries, and the loader (ld-linux, printed as "/path (addr)" or "name => /path (addr)")
    ldd "$path" | while IFS= read -r line; do
        lib=$(echo "$line" | sed -n 's/.*=> \(\/[^ ]*\) (.*/\1/p; t; s/^[[:space:]]*\(\/[^ ]*\) (.*/\1/p')
        [ -n "$lib" ] || continue
        case "${lib##*/}" in
            ld-linux*) cp -L "$lib" "$DEST$H/lib/ld.so" ;;
            *)         cp -L "$lib" "$DEST$H/lib/${lib##*/}" ;;
        esac
    done
    [ -f "$DEST$H/lib/ld.so" ] || { echo "copy-host-tools: no loader found for $path" >&2; exit 1; }
    chmod 755 "$DEST$H/lib/ld.so"
    cat > "$DEST/usr/bin/$name" <<EOF
#!/bin/sh
# $name from the build host, run with its own libraries (see tools/overlay-common/copy-host-tools.sh)
exec $H/lib/ld.so --library-path $H/lib --argv0 "\$0" $H/bin/$name "\$@"
EOF
    chmod 755 "$DEST/usr/bin/$name"
done
