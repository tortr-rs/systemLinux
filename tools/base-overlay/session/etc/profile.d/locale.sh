# systemLinux: point glibc at the locale archive goget installed (glibc-locales), so any locale
# named in /etc/locale.conf's LANG= actually works, not just C.UTF-8. To add more than en_US.UTF-8,
# see the archive's available locales with `localedef --list-archive`; the installer/handbook sets
# LANG= for the account's chosen language.
for f in /nix/store/*-glibc-locales-*/lib/locale/locale-archive; do
    [ -f "$f" ] && export LOCALE_ARCHIVE="$f"
    break
done
