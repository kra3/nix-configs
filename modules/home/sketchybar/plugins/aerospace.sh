#!/usr/bin/env bash
# $1 = workspace ID this item represents
# $2 = this workspace's accent color
# $NAME = sketchybar item; $FOCUSED_WORKSPACE = set by aerospace_workspace_change
#
# Per-monitor: pin each workspace item to the sketchybar `display` of the monitor
# it lives on, highlight the visible one, and hide non-persistent empty
# workspaces so each bar shows only its own live workspaces.

COLOR="${2:-0xffcdd6f4}"
SID="$1"
PERSISTENT=" 1 2 3 "

# Hide non-persistent workspaces that hold no windows.
if [[ "$PERSISTENT" != *" $SID "* ]]; then
    COUNT="$(aerospace list-windows --workspace "$SID" 2>/dev/null | grep -c .)"
    if [ "${COUNT:-0}" -eq 0 ]; then
        sketchybar --set "$NAME" drawing=off
        exit 0
    fi
fi

# sketchybar `display` follows NSScreen order, which aerospace exposes as
# monitor-appkit-nsscreen-screens-id — NOT monitor-id (aerospace re-sorts those
# by position, so they disagree). Keep monitor-id for the --monitor query below.
LINE="$(aerospace list-workspaces --all --format '%{workspace}|%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null \
        | awk -F'|' -v w="$SID" '$1 == w { print $2 "|" $3; exit }')"
MON="${LINE%%|*}"
DISP="${LINE##*|}"
DISP="${DISP:-1}"

# Visible (focused) workspace on that monitor; fall back to the global focus.
VIS="$(aerospace list-workspaces --monitor "$MON" --visible --format '%{workspace}' 2>/dev/null)"
FOCUS="${VIS:-$FOCUSED_WORKSPACE}"

if [ "$SID" = "$FOCUS" ]; then
    sketchybar --set "$NAME" \
        drawing=on               \
        display="$DISP"          \
        background.drawing=on    \
        background.color="$COLOR" \
        label.color=0xff1e1e2e
else
    sketchybar --set "$NAME" \
        drawing=on               \
        display="$DISP"          \
        background.drawing=off   \
        label.color="$COLOR"
fi
