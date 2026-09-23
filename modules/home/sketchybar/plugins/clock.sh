#!/usr/bin/env bash
# 24-hour clock. Popup (on click) shows the month calendar, world clocks, and
# today's agenda.
#   clock.sh         → routine: refresh the label
#   clock.sh toggle  → click: toggle popup, populate calendar + events
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Shared popup style; explicit row width prevents clipping. Menlo aligns columns.
PW=240
F_HEAD="Helvetica Neue:Bold:13.0"
F_MONO="Menlo:Regular:12.0"
F_ROW="Helvetica Neue:Regular:13.0"

add_header() { # $1=id-suffix  $2=text ; appends to CLK_ARGS
    CLK_ARGS+=(--add item "clock.pop.$1" popup."$NAME"
        --set "clock.pop.$1" icon.drawing=off label="$2"
            label.font="$F_HEAD" label.color=0xfff9e2af label.align=left
            width="$PW" label.padding_left=10
            background.drawing=on background.color=0x22313244 background.height=20 background.corner_radius=4)
}

add_event() { # $1=id-suffix  $2=label  $3=color (default text) ; appends to CLK_ARGS
    CLK_ARGS+=(--add item "clock.pop.$1" popup."$NAME"
        --set "clock.pop.$1" icon.drawing=off label="$2"
            label.font="$F_ROW" label.color="${3:-0xffcdd6f4}" label.max_chars=40
            label.align=left width="$PW" label.padding_left=16
            background.drawing=on background.color=0x00000000 background.height=22)
}

populate() {
    # Build the whole popup in one sketchybar call (fast).
    local CLK_ARGS=(--remove '/clock\.pop\..*/')

    # Month grid via BSD /usr/bin/cal (nix's util-linux cal shadows it in PATH).
    local i=0 line
    while IFS= read -r line; do
        CLK_ARGS+=(--add item "clock.pop.cal$i" popup."$NAME"
            --set "clock.pop.cal$i" icon.drawing=off label="$line"
                label.font="$F_MONO" label.color=0xffcdd6f4 label.align=center width="$PW"
                background.drawing=on background.color=0x00000000 background.height=22)
        i=$((i + 1))
    done < <(/usr/bin/cal)

    # World clocks: PST / IST / UTC (Menlo so the times line up).
    add_header tzhdr "World Clocks"
    local z=0 zn zt
    for zn in "PST|America/Los_Angeles" "IST|Asia/Kolkata" "UTC|UTC"; do
        zt="$(TZ="${zn#*|}" date '+%a %H:%M')"
        CLK_ARGS+=(--add item "clock.pop.tz$z" popup."$NAME"
            --set "clock.pop.tz$z" icon.drawing=off
                label="$(printf '%-5s %s' "${zn%%|*}" "$zt")"
                label.font="$F_MONO" label.color=0xffcdd6f4 label.align=left width="$PW" label.padding_left=16
                background.drawing=on background.color=0x00000000 background.height=22)
        z=$((z + 1))
    done

    # Today's agenda in two sections: the next upcoming event (not yet started),
    # then everything else still to come (in-progress or later). Finished events
    # are dropped. icalBuddy emits "START - END<TAB>Title" sorted by start; "..."
    # marks a bound outside today. (Needs Calendar access granted on first run.)
    if command -v icalBuddy >/dev/null 2>&1; then
        local now_min range title start end sm em disp next_row k row
        local rest_rows=()
        now_min=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        next_row=""
        while IFS=$'\t' read -r range title; do
            [ -n "$title" ] || continue
            start="${range%% - *}"; end="${range##* - }"
            case "$start" in [0-9][0-9]:[0-9][0-9]) sm=$((10#${start%%:*} * 60 + 10#${start##*:})) ;; *) sm=-1 ;; esac
            case "$end" in [0-9][0-9]:[0-9][0-9]) em=$((10#${end%%:*} * 60 + 10#${end##*:})) ;; *) em=-1 ;; esac
            { [ "$em" -ge 0 ] && [ "$em" -le "$now_min" ]; } && continue # already ended
            case "$start" in [0-9][0-9]:[0-9][0-9]) disp="$start  $title" ;; *) disp="$title" ;; esac
            if [ "$sm" -gt "$now_min" ] && [ -z "$next_row" ]; then
                next_row="$disp" # soonest not-yet-started event
            else
                rest_rows+=("$disp") # in-progress, all-day, or later upcoming
            fi
        done < <(icalBuddy -nc -nrd -po "datetime,title" -iep "datetime,title" -b "" -ps "|\t|" -tf "%H:%M" -df "" eventsToday 2>/dev/null)

        add_header nexthdr "Next event"
        if [ -n "$next_row" ]; then add_event next0 "$next_row"; else add_event next0 "Nothing upcoming" 0xff6c7086; fi

        add_header resthdr "Remaining today"
        if [ "${#rest_rows[@]}" -gt 0 ]; then
            k=0
            for row in "${rest_rows[@]}"; do add_event "rest$k" "$row"; k=$((k + 1)); done
        else
            add_event rest0 "None" 0xff6c7086
        fi
    fi

    sketchybar "${CLK_ARGS[@]}"
}

# Click (passes "toggle") handled before the SENDER dismiss below: sketchybar
# leaks the last event's SENDER into click_script, so a click can arrive as
# mouse.exited.global and be swallowed. The event script passes no arg.
if [ "$1" = "toggle" ]; then
    if [ "$(sketchybar --query "$NAME" 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)" = "on" ]; then
        sketchybar --set "$NAME" popup.drawing=off
    else
        populate
        sketchybar --set "$NAME" popup.drawing=on
    fi
    exit 0
fi

# Pointer left the item and its popup → dismiss (auto-close on focus loss).
if [ "$SENDER" = "mouse.exited.global" ]; then
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
fi

sketchybar --set "$NAME" label="$(date '+%a %b %-d %H:%M')"
