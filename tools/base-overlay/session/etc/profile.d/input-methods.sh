# systemLinux: point GTK/Qt programs at ibus/fcitx5 if one is running. Neither is started
# automatically (there is no desktop session to launch it from) -- run `ibus-daemon -drx` or
# `fcitx5` by hand, or from a window manager's own startup file, once one is installed.
export GTK_IM_MODULE=${GTK_IM_MODULE:-ibus}
export QT_IM_MODULE=${QT_IM_MODULE:-ibus}
export XMODIFIERS=${XMODIFIERS:-@im=ibus}
