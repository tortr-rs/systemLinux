#!/bin/sh
# Download URL to FILE and check its SHA-256. Needs only curl and sha256sum on the build host.
# usage: fetch.sh URL SHA256 FILE
set -eu
URL=${1:?usage: fetch.sh URL SHA256 FILE} SHA=${2:?} OUT=${3:?}
curl -fsSL --retry 3 -o "$OUT" "$URL"
[ "$(sha256sum "$OUT" | cut -d' ' -f1)" = "$SHA" ] || { echo "fetch: checksum mismatch for $URL" >&2; rm -f "$OUT"; exit 1; }
