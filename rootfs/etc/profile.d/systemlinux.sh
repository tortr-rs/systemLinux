# systemLinux login banner (installed by goget)
if [ -t 1 ] && [ -z "${SYSTEMLINUX_BANNER:-}" ]; then
	SYSTEMLINUX_BANNER=1
	export SYSTEMLINUX_BANNER
	printf '\033[38;5;179m'
	cat <<'SYSTEMLINUX_CAT'

        ,
       /|\
     ,/ | \,
     \\ | //
    ,/\\|//\,
    \\ \|/ //
     '\ | /'
   \     |     /
    '-.  |  .-'
        \|/
         |

SYSTEMLINUX_CAT
	printf '  systemLinux v1.0 GNU/Linux\n\n\033[0m'
fi
