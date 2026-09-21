#!/bin/bash
# Remove Portage and the Gentoo-specific tooling from a staged image (systemLinux 0.6: packages come from
# `goget`, not from emerge). Before the package database goes, the names of the base packages are written to
# usr/share/goget/base-provides so goget never tries to install a second glibc or ncurses.
# usage: strip-gentoo.sh STAGE     (works on any directory; run under fakeroot when the image needs root ownership)
set -euo pipefail
S=${1:?usage: strip-gentoo.sh STAGE}
cd "$S"
mkdir -p usr/share/goget
if [ -d var/db/pkg ]; then
    for d in var/db/pkg/*/*/; do
        [ -d "$d" ] || continue
        cpv=$(basename "$d"); cat=$(basename "$(dirname "$d")")
        n=$(echo "$cpv" | sed -E 's/-[0-9][^-]*(-r[0-9]+)?$//')
        echo "$n"; echo "$cat/$n"
    done | sort -u > usr/share/goget/base-provides
fi
rm -rf var/db/repos var/db/pkg var/cache/distfiles var/cache/binpkgs var/lib/portage var/lib/gentoo \
       etc/portage etc/eselect usr/share/portage usr/share/eselect usr/lib/portage usr/share/gentoolkit \
       etc/gentoo-release var/tmp/portage var/log/portage
for p in usr/lib/python3*/site-packages; do
    [ -d "$p" ] || continue
    rm -rf "$p"/portage "$p"/_emerge "$p"/gentoolkit "$p"/repoman "$p"/glsa* "$p"/portage-*.dist-info "$p"/gemato* "$p"/pkgcore* "$p"/snakeoil*
done
for b in emerge ebuild eselect equery emaint env-update etc-update dispatch-conf quickpkg portageq gcc-config \
         binutils-config glsa-check regenworld egencache emerge-webrsync revdep-rebuild eclean eclean-dist eclean-pkg \
         euse eshowkw equo ekeyword enalyze epkginfo eread elog-notify regenworld fixpackages archive-conf \
         ebuild.sh ebuild-helpers repoman pquery pmaint pkgdev pkgcheck; do
    rm -rf "usr/bin/$b" "usr/sbin/$b" "bin/$b" "sbin/$b" "usr/lib/python-exec/python3*/$b" 2>/dev/null || true
done
# the portage user/group only existed for emerge
for f in etc/passwd etc/group etc/shadow etc/gshadow; do [ -f "$f" ] && sed -i '/^portage:/d' "$f"; done
sed -i -E 's/,portage\b//; s/:portage,/:/; s/:portage$/:/' etc/group 2>/dev/null || true
