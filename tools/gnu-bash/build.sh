#!/bin/bash
# Build GNU bash as a static binary (no shared libraries, so it runs on any base and does not
# depend on the target's libtinfo). Needs gcc, make, curl, libc.a and libtinfo.a (libncurses-dev).
# usage: ./build.sh            -> ./bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VER=${BASH_VER:-5.3}
WORK=${WORK:-$HOME/.cache/systemlinux-bash}
mkdir -p "$WORK" && cd "$WORK"
[ -f "bash-$VER.tar.gz" ] || curl -fsSL -o "bash-$VER.tar.gz" "https://ftp.gnu.org/gnu/bash/bash-$VER.tar.gz"
# verify against the GNU keyring-free fallback: the tarball must at least be a valid gzip tar
tar -tzf "bash-$VER.tar.gz" >/dev/null
rm -rf "bash-$VER" && tar -xzf "bash-$VER.tar.gz" && cd "bash-$VER"
TERMCAP_LIB=-ltinfo ./configure --prefix=/usr --enable-static-link --without-bash-malloc --disable-nls \
    --with-curses --enable-readline --enable-history bash_cv_termcap_lib=libtinfo >/dev/null
make -j"$(nproc)" LOCAL_LIBS="-ltinfo" SHOBJ_LIBS="-ltinfo" >/dev/null
strip bash
install -m755 bash "$HERE/bash"
"$HERE/bash" --version | head -1
ldd "$HERE/bash" 2>&1 | head -1
