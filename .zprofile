
# Start labwc automatically on TTY1 (only when not already in a graphical session)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
    exec labwc
fi
