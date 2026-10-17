#!/bin/sh
# Validate the dinit service descriptions in rootfs/etc/dinit.d with dinit-check (syntax, dependencies,
# cycles). Executables are looked up under rootfs/ instead of the host, so "could not stat" warnings
# are only ignored for programs that exist in the image tree or are installed by the build (dinit's own).
# usage: check-services.sh   (dinit-check must be on PATH, or set DINIT_CHECK)
#        CHROOT=ROOTFS check-services.sh   (as root: run the image's own dinit-check inside it, on any host)
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
DC=${DINIT_CHECK:-dinit-check}
if [ -n "${CHROOT:-}" ]; then
    out=$("$REPO/tools/overlay-common/chroot-run.sh" "$CHROOT" "dinit-check -d /etc/dinit.d boot" 2>&1) || true
else
    out=$("$DC" -d "$REPO/rootfs/etc/dinit.d" boot 2>&1) || true
fi
echo "$out"
bad=$(echo "$out" | grep -E "^Service '.*': (error|warning)" | grep -v 'could not stat' || true)
bad="$bad$(echo "$out" | grep -iE '^dinit-check:|cycle|not found|no such service' || true)"
# every helper script referenced from a service must exist in the repo tree and be executable
for cmd in $(cat "$REPO"/rootfs/etc/dinit.d/* 2>/dev/null | sed -n 's/^\(stop-\)\?command[[:space:]]*=[[:space:]]*\(\/usr\/lib\/dinit\/[^ ]*\).*/\2/p'); do
    [ -x "$REPO/rootfs$cmd" ] || bad="$bad
missing or not executable: $cmd"
done
[ -z "$(echo "$bad" | tr -d '[:space:]')" ] || { echo "dinit service check FAILED:$bad" >&2; exit 1; }
echo "dinit service check OK"
