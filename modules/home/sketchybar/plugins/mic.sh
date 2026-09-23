#!/run/current-system/sw/bin/bash
source "${0%/*}/../theme.sh"
# Mic state glyph from the default input volume (0 = muted/off).
IN="$(osascript -e 'input volume of (get volume settings)' 2>/dev/null)"

if [ -z "$IN" ] || [ "$IN" -eq 0 ] 2>/dev/null; then
    sketchybar --set "$NAME" icon="󰍭" icon.color="$DISABLED" # muted
else
    sketchybar --set "$NAME" icon="󰍬" icon.color="$BAR_TEXT" # live
fi
