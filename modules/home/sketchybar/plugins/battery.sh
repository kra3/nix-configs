#!/run/current-system/sw/bin/bash
source "${0%/*}/../theme.sh"
# Show battery percentage with a Nerd Font icon.
PERCENTAGE=$(pmset -g batt | grep -Eo '[0-9]+%' | tr -d '%')
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ -z "$PERCENTAGE" ]; then
    # No battery (Mac mini, Mac Studio, Mac Pro) — hide the item instead of
    # showing a permanent "?".
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

if [ -n "$CHARGING" ]; then
    ICON="󰚥"                    # plugged in (AC power)
    COLOR="$OK"            # green
elif [ "$PERCENTAGE" -ge 80 ]; then
    ICON="󰁹" COLOR="$BAR_TEXT"   # full
elif [ "$PERCENTAGE" -ge 60 ]; then
    ICON="󰂁" COLOR="$BAR_TEXT"
elif [ "$PERCENTAGE" -ge 40 ]; then
    ICON="󰁾" COLOR="$WARN"   # yellow
elif [ "$PERCENTAGE" -ge 20 ]; then
    ICON="󰁼" COLOR="$CRIT"   # red-ish
else
    ICON="󰁺" COLOR="$CRIT"   # critical
fi

sketchybar --set "$NAME" drawing=on icon="$ICON" icon.color="$COLOR" label="${PERCENTAGE}%"
