# systemLinux: point GTK/Qt programs at fcitx5 for CJK and other input methods. It is not started
# automatically (there is no desktop session to launch it from) -- run `fcitx5` by hand, or from a
# window manager's own startup file, once one is installed.
export GTK_IM_MODULE=${GTK_IM_MODULE:-fcitx}
export QT_IM_MODULE=${QT_IM_MODULE:-fcitx}
export XMODIFIERS=${XMODIFIERS:-@im=fcitx}
