# systemLinux: log in on the first virtual console and GNOME starts (Wayland). Other consoles stay text.
if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = /dev/tty1 ] \
   && [ "$(id -u)" -ge 1000 ] && [ -x /usr/bin/gnome-session ]; then
    # crash-loop guard: if GNOME was started less than 20 seconds ago, stay on the text console
    # (a shell and the log at ~/.local/share/systemlinux-gnome.log help to find out why)
    _stamp=/tmp/.systemlinux-gnome-start-$(id -u)
    _now=$(date +%s)
    _last=$(cat "$_stamp" 2>/dev/null || echo 0)
    echo "$_now" > "$_stamp"
    if [ $((_now - _last)) -ge 20 ]; then
        export XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=gnome XDG_CURRENT_DESKTOP=GNOME
        export MOZ_ENABLE_WAYLAND=1
        mkdir -p "$HOME/.local/share"
        exec dbus-run-session gnome-session >"$HOME/.local/share/systemlinux-gnome.log" 2>&1
    else
        echo "GNOME exited right after starting; see ~/.local/share/systemlinux-gnome.log (log out and in to retry)."
    fi
fi
