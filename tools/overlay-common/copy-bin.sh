#!/bin/sh
# Copy host programs and the shared libraries they need into a directory tree (same paths as on the
# host). Used for the initramfs, which is its own small world; the live image uses copy-host-tools.sh.
# usage: copy-bin.sh DEST PROGRAM...
set -eu
DEST=${1:?usage: copy-bin.sh DEST PROGRAM...}; shift
for p in "$@"; do
    path=$(command -v "$p" 2>/dev/null || true)
    [ -n "$path" ] || { echo "copy-bin: $p not found on the build host" >&2; exit 1; }
    path=$(readlink -f "$path")
    mkdir -p "$DEST$(dirname "$path")"; cp -L "$path" "$DEST$path"
    # Check for missing libraries
    if ldd "$path" 2>/dev/null | grep -q 'not found'; then echo "copy-bin: missing libraries for $path" >&2; exit 1; fi
    # Parse ldd output - handle both "=> /path/to/lib" and " /path/to/lib (" formats
    ldd "$path" 2>/dev/null | while IFS= read -r line; do
        # Extract library path from various ldd output formats
        lib=$(echo "$line" | sed -n 's/.*=> \(.*\) (.*/\1/p; s/^[[:space:]]*\(.*\) (.*/\1/p')
        if [ -n "$lib" ] && [ "$lib" != "linux-vdso.so.1" ] && [ "$lib" != "ld-linux-x86-64.so.2" ]; then
            lib=$(readlink -f "$lib" 2>/dev/null || echo "$lib")
            if [ -f "$lib" ]; then
                mkdir -p "$DEST$(dirname "$lib")"
                cp -L "$lib" "$DEST$lib"
            fi
        fi
    done
done
