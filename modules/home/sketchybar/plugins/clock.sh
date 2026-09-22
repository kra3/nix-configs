#!/usr/bin/env bash
# 24-hour clock. Popup (on click) shows the month calendar, world clocks, and
# today's agenda.
#   clock.sh         → routine: refresh the label
#   clock.sh toggle  → click: toggle popup, populate calendar + events
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Shared popup style. Explicit width on every row is what stops content from
# collapsing/clipping; SF Pro/SF Mono have normal line metrics (Nerd Font's are
# tall, which is what bloated the row spacing). Popup background/blur come from
# the bar's --default, so rows carry no background of their own.
PW=240
F_HEAD="Helvetica Neue:Bold:13.0"
F_MONO="Menlo:Regular:12.0"
F_ROW="Helvetica Neue:Regular:13.0"

add_header() { # $1=id-suffix  $2=text
    sketchybar --add item "clock.pop.$1" popup."$NAME" \
        --set "clock.pop.$1" icon.drawing=off label="$2" \
            label.font="$F_HEAD" label.color=0xfff9e2af label.align=left \
            width="$PW" label.padding_left=10 \
            background.drawing=on background.color=0x22313244 \
            background.height=20 background.corner_radius=4
}

populate() {
    sketchybar --remove '/clock\.pop\..*/' 2>/dev/null

    # Month grid: one popup row per line of BSD /usr/bin/cal (nix's util-linux
    # `cal` shadows it in PATH). SF Mono keeps the columns aligned. A transparent
    # fixed-height background compacts the row (otherwise rows floor to bar height).
    local i=0 line
    while IFS= read -r line; do
        sketchybar --add item "clock.pop.cal$i" popup."$NAME" \
            --set "clock.pop.cal$i" icon.drawing=off label="$line" \
                label.font="$F_MONO" label.color=0xffcdd6f4 \
                label.align=center width="$PW" \
                background.drawing=on background.color=0x00000000 background.height=22
        i=$((i + 1))
    done < <(/usr/bin/cal)

    # World clocks: PST / IST / UTC (SF Mono so the times line up).
    add_header tzhdr "World Clocks"
    local z=0 zn zt
    for zn in "PST|America/Los_Angeles" "IST|Asia/Kolkata" "UTC|UTC"; do
        zt="$(TZ="${zn#*|}" date '+%a %H:%M')"
        sketchybar --add item "clock.pop.tz$z" popup."$NAME" \
            --set "clock.pop.tz$z" icon.drawing=off \
                label="$(printf '%-5s %s' "${zn%%|*}" "$zt")" \
                label.font="$F_MONO" label.color=0xffcdd6f4 \
                label.align=left width="$PW" label.padding_left=16 \
                background.drawing=on background.color=0x00000000 background.height=22
        z=$((z + 1))
    done

    # Today's agenda (needs Calendar access granted to sketchybar on first run).
    command -v icalBuddy >/dev/null 2>&1 || return 0
    add_header hdr "Today"
    local j=0 ev
    while IFS= read -r ev; do
        [ -n "$ev" ] || continue
        sketchybar --add item "clock.pop.ev$j" popup."$NAME" \
            --set "clock.pop.ev$j" icon.drawing=off label="${ev:0:40}" \
                label.font="$F_ROW" label.color=0xffcdd6f4 label.max_chars=40 \
                label.align=left width="$PW" label.padding_left=16 \
                background.drawing=on background.color=0x00000000 background.height=22
        j=$((j + 1))
    done < <(icalBuddy -nc -nrd -eep "notes,url,location,attendees" -b "• " -ps "|  |" eventsToday 2>/dev/null)
    [ "$j" -eq 0 ] && sketchybar --add item "clock.pop.ev0" popup."$NAME" \
        --set "clock.pop.ev0" icon.drawing=off label="No events" label.color=0xff6c7086 \
            label.font="$F_ROW" label.align=left width="$PW" label.padding_left=16 \
            background.drawing=on background.color=0x00000000 background.height=22
}

# Pointer left the item and its popup → dismiss (auto-close on focus loss).
if [ "$SENDER" = "mouse.exited.global" ]; then
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
fi

if [ "$1" = "toggle" ]; then
    if [ "$(sketchybar --query "$NAME" 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)" = "on" ]; then
        sketchybar --set "$NAME" popup.drawing=off
    else
        populate
        sketchybar --set "$NAME" popup.drawing=on
    fi
    exit 0
fi

sketchybar --set "$NAME" label="$(date '+%a %b %-d %H:%M')"
