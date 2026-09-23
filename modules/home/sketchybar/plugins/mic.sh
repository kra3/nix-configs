#!/run/current-system/sw/bin/bash
# Mic state glyph from the default input volume (0 = muted/off).
IN="$(osascript -e 'input volume of (get volume settings)' 2>/dev/null)"

if [ -z "$IN" ] || [ "$IN" -eq 0 ] 2>/dev/null; then
    sketchybar --set "$NAME" icon="󰍭" icon.color=0xff6c7086 # muted
else
    sketchybar --set "$NAME" icon="󰍬" icon.color=0xffcdd6f4 # live
fi
