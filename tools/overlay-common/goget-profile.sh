# goget (nixpkgs packages): put installed programs, desktop entries and icons where the shell (and any desktop you install later) finds them
for _p in "$HOME/.local/state/goget/profile/current" /nix/var/goget/profiles/system/current; do
    case ":$PATH:" in *":$_p/bin:"*) ;; *) PATH="$_p/bin:$PATH" ;; esac
    XDG_DATA_DIRS="$_p/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
done
unset _p
export PATH XDG_DATA_DIRS
# programs from the Nix cache look for certificates here
if [ -z "${SSL_CERT_FILE:-}" ] && [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
fi
