#!/run/current-system/sw/bin/bash
source "${0%/*}/../theme.sh"
# Show CPU usage percentage with color-coded Nerd Font icon.

CPU=$(top -l 1 -n 0 | awk '/CPU usage/ {gsub(/%/,""); print int($3 + $5)}')

if [ "$CPU" -ge 80 ]; then
    COLOR="$CRIT"   # red
elif [ "$CPU" -ge 50 ]; then
    COLOR="$WARN"   # yellow
else
    COLOR="$OK"   # green
fi

sketchybar --set "$NAME" icon.color="$COLOR" label="${CPU}%"
