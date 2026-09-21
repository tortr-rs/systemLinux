# systemLinux login banner
if [ -t 1 ] && [ -z "${SYSTEMLINUX_BANNER:-}" ]; then
	SYSTEMLINUX_BANNER=1
	export SYSTEMLINUX_BANNER
	printf '\033[38;5;179m'
	cat <<'SYSTEMLINUX_WHEAT'

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

SYSTEMLINUX_WHEAT
	printf '  systemLinux v@@VER@@ GNU/Linux\n\n\033[0m'
fi
