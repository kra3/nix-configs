#!/run/current-system/sw/bin/bash
# 24-hour clock. Popup (on click) shows the month calendar, an agenda split into
# the next event and everything still to come, due tasks, and world clocks.
#   clock.sh         → routine: refresh label + running-meeting/task indicators
#   clock.sh toggle  → click: toggle popup, (re)build its contents
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# launchd starts us with no locale (C), which makes bash substring / fold / icalBuddy
# byte-wise and can split multibyte chars into invalid UTF-8. Force UTF-8.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
source "$(dirname "$0")/../theme.sh" # liquid-glass palette

PW=200
WRAP=26 # conservative word-wrap width for the proportional title font
F_HEAD="Helvetica Neue:Bold:13.0"
F_MONO="Menlo:Regular:12.0"
F_ROW="Helvetica Neue:Regular:12.0"
F_DET="Helvetica Neue:Regular:11.0"
F_GLYPH="MesloLGS Nerd Font:Regular:12.0"
C_TEXT="$POPUP_TEXT"
C_DIM="$POPUP_DIM"
C_MUTE="$DISABLED"
C_RED="$CRIT"   # overdue task (kept)
C_GREEN="$OK" # running meeting (kept)
C_BLUE="$SECONDARY"
# ZEBRA_A / ZEBRA_B come from theme.sh
US=$'\037' # record field separator: non-whitespace so empty fields aren't collapsed by read
H_HEAD=18  # section header row height
H_ROW=8   # standard row (calendar, tasks, world clocks)
H_TITLE=13 # event title line (tight so wrapped lines read as one unit)
H_DET=11   # event detail line (time · location)
PL=16      # left margin shared by all content rows
G_WEBEX=""   # nf-fa-video_camera
G_MEET="󰕧"    # nf-md-video
G_TASK="󰝖"    # nf-md-format-list-checks

# Common icalBuddy options: one collapsed line per event, tab-separated properties,
# 24h start-end times, no date. Property names are kept (location:/notes:) so fields
# stay identifiable even when some are absent (icalBuddy omits empty properties,
# which would otherwise shift positional parsing). -nnr keeps notes on one line.
IC=(icalBuddy -nc -nrd -nnr " " -b "" -ps "|\t|" -tf "%H:%M" -df "")

# Popup rows are locked to the bar height (36px), so background.height can't
# tighten them; y_offset pulls each wrapped line + the detail up within its slot
# so a multi-line event reads as one unit. SHIFT ~= slot - desired line spacing.
SHIFT=8

add_header() { # $1=id-suffix  $2=text ; appends to CLK_ARGS
    CLK_ARGS+=(--add item "clock.pop.$1" popup."$NAME"
        --set "clock.pop.$1" icon.drawing=off label="$2"
            label.font="$F_HEAD" label.color="$POPUP_HEAD" label.align=left
            width="$PW" label.padding_left="$PL"
            background.drawing=on background.color="$HEADER_BG" background.height="$H_HEAD" background.corner_radius=4)
}

# Emit one event as a group: word-wrapped title lines + a detail line, all sharing
# one zebra shade and (for a webex event) one click target. $1=id-prefix $2=index
# $3=start $4=end $5=title $6=location $7=webex-url
emit_event() {
    local pre="$1" idx="$2" start="$3" end="$4" title="$5" loc="$6" webex="$7"
    local bg="$ZEBRA_A"; [ $((idx % 2)) -eq 1 ] && bg="$ZEBRA_B"
    local click=""; [ -n "$webex" ] && click="open '$webex'; sketchybar --set $NAME popup.drawing=off"
    local lines=() wline
    while IFS= read -r wline; do lines+=("$wline"); done < <(printf '%s\n' "$title" | fold -s -w "$WRAP")
    local n=${#lines[@]} ln off
    for ((ln = 0; ln < n; ln++)); do
        off=$((ln * SHIFT)) # pull each wrapped line up toward the previous one
        CLK_ARGS+=(--add item "clock.pop.$pre${idx}_$ln" popup."$NAME"
            --set "clock.pop.$pre${idx}_$ln" icon.drawing=off label="${lines[ln]}"
                label.font="$F_ROW" label.color="$C_TEXT" label.align=left label.max_chars=38
                width="$PW" label.padding_left="$PL" y_offset="$off"
                background.drawing=on background.color="$bg" background.height="$H_TITLE")
        [ -n "$click" ] && CLK_ARGS+=(click_script="$click")
    done
    # Detail line: time · location, with a webex glyph when the event has a link;
    # pulled up under the last title line so the event reads as one unit.
    local ts="$start" te="$end"
    [ "$start" = "..." ] && ts=".."; [ "$end" = "..." ] && te=".."
    local det="$ts-$te"; [ -n "$loc" ] && det="$det · ${loc:0:24}"
    off=$((n * SHIFT))
    CLK_ARGS+=(--add item "clock.pop.$pre${idx}_d" popup."$NAME"
        --set "clock.pop.$pre${idx}_d" label="$det" y_offset="$off"
            label.font="$F_DET" label.color="$C_DIM" label.align=left
            width="$PW" background.drawing=on background.color="$bg" background.height="$H_DET")
    if [ -n "$webex" ]; then
        CLK_ARGS+=(icon="$G_WEBEX" icon.font="$F_GLYPH" icon.color="$C_BLUE" icon.padding_left="$PL" label.padding_left=6 click_script="$click")
    else
        CLK_ARGS+=(icon.drawing=off label.padding_left="$PL")
    fi
}

# Rebuild the popup contents (month grid, agenda, tasks, world clocks).
populate() {
    local CLK_ARGS=(--remove '/clock\.pop\..*/')

    # Month grid via BSD /usr/bin/cal (nix's util-linux cal shadows it in PATH).
    local i=0 line
    while IFS= read -r line; do
        CLK_ARGS+=(--add item "clock.pop.cal$i" popup."$NAME"
            --set "clock.pop.cal$i" icon.drawing=off label="$line"
                label.font="$F_MONO" label.color="$C_TEXT" label.align=left width="$PW" label.padding_left="$PL"
                background.drawing=on background.color=0x00000000 background.height="$H_ROW")
        i=$((i + 1))
    done < <(/usr/bin/cal)

    # Agenda from today's events, classified against the current time: finished
    # events (end <= now) are dropped; in-progress (and all-day) → Now; the first
    # not-yet-started → Next; the rest → Later. eventsToday (not eventsFrom:now,
    # which drops events starting within the next minute or two). Property names
    # are kept so location/notes are matched by prefix even when some are absent
    # (icalBuddy omits empty properties, which would shift positional parsing).
    if command -v icalBuddy >/dev/null 2>&1; then
        local NEXT_REC="" ; local NOW_RECS=() ; local LATER_RECS=()
        local props="datetime,title,location,notes"
        local now_min=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        local line range title loc notes start end sm em webex rec f F k s e t l w
        while IFS= read -r line; do
            IFS=$'\t' read -ra F <<<"$line"
            title="${F[1]}"; [ -n "$title" ] || continue # skip location-continuation lines
            range="${F[0]}"; loc=""; notes=""
            for f in "${F[@]:2}"; do
                case "$f" in
                    "location: "*) loc="${f#location: }" ;;
                    "notes: "*) notes="${f#notes: }" ;;
                esac
            done
            start="${range%% - *}"; end="${range##* - }"
            case "$start" in [0-9][0-9]:[0-9][0-9]) sm=$((10#${start%%:*} * 60 + 10#${start##*:})) ;; *) sm=-1 ;; esac
            case "$end" in [0-9][0-9]:[0-9][0-9]) em=$((10#${end%%:*} * 60 + 10#${end##*:})) ;; *) em=-1 ;; esac
            { [ "$em" -ge 0 ] && [ "$em" -le "$now_min" ]; } && continue # already finished
            # A webex link may live in either location or notes; a bare-URL location
            # is noise once we have the glyph+click, so blank it for display.
            webex="$(printf '%s %s' "$loc" "$notes" | grep -oE 'https://[a-zA-Z0-9.]*webex\.com/[^ ]+' | head -1)"
            case "$loc" in http*) loc="" ;; esac
            rec="$start${US}$end${US}$title${US}$loc${US}$webex"
            if [ "$sm" -gt "$now_min" ]; then
                if [ -z "$NEXT_REC" ]; then NEXT_REC="$rec"; else LATER_RECS+=("$rec"); fi
            else
                NOW_RECS+=("$rec") # in-progress or all-day
            fi
        done < <("${IC[@]}" -po "$props" -iep "$props" eventsToday 2>/dev/null)

        if [ "${#NOW_RECS[@]}" -gt 0 ]; then
            add_header nowhdr "Now"
            k=0
            for rec in "${NOW_RECS[@]}"; do
                IFS="$US" read -r s e t l w <<<"$rec"; emit_event now "$k" "$s" "$e" "$t" "$l" "$w"; k=$((k + 1))
            done
        fi

        add_header nexthdr "Next event"
        if [ -n "$NEXT_REC" ]; then
            IFS="$US" read -r s e t l w <<<"$NEXT_REC"; emit_event nx 0 "$s" "$e" "$t" "$l" "$w"
        else
            CLK_ARGS+=(--add item clock.pop.nx0 popup."$NAME"
                --set clock.pop.nx0 icon.drawing=off label="Nothing upcoming" label.color="$C_MUTE"
                    label.font="$F_ROW" label.align=left width="$PW" label.padding_left="$PL"
                    background.drawing=on background.color=0x00000000 background.height="$H_ROW")
        fi

        if [ "${#LATER_RECS[@]}" -gt 0 ]; then
            add_header laterhdr "Later today"
            k=0
            for rec in "${LATER_RECS[@]}"; do
                IFS="$US" read -r s e t l w <<<"$rec"; emit_event lt "$k" "$s" "$e" "$t" "$l" "$w"; k=$((k + 1))
            done
        fi

        # Tasks due within 3 months (overdue included). icalBuddy marks overdue
        # with a "!" bullet, others with "•"; -itp title drops the due-date line.
        local tj=0 tline col txt tcut
        tcut="$(date -v+3m '+%Y-%m-%d')"
        while IFS= read -r tline; do
            case "$tline" in
                "! "*) col="$C_RED"; txt="${tline#! }" ;;
                "• "*) col="$C_TEXT"; txt="${tline#• }" ;;
                *) continue ;; # blank / continuation line
            esac
            [ "$tj" -eq 0 ] && add_header taskhdr "Tasks"
            CLK_ARGS+=(--add item "clock.pop.t$tj" popup."$NAME"
                --set "clock.pop.t$tj" icon="$G_TASK" icon.font="$F_GLYPH" icon.color="$col" icon.padding_left="$PL"
                    label="${txt:0:40}" label.font="$F_ROW" label.color="$col" label.align=left
                    label.padding_left=6 width="$PW"
                    background.drawing=on background.color=0x00000000 background.height="$H_ROW")
            tj=$((tj + 1))
        done < <(icalBuddy -nc -nrd -npn -stda -itp "title" "tasksDueBefore:$tcut" 2>/dev/null)
    fi

    # World clocks: PST / IST / UTC (Menlo so the times line up).
    add_header tzhdr "World Clocks"
    local z=0 zn zt
    for zn in "PST|America/Los_Angeles" "IST|Asia/Kolkata" "UTC|UTC"; do
        zt="$(TZ="${zn#*|}" date '+%a %H:%M')"
        CLK_ARGS+=(--add item "clock.pop.tz$z" popup."$NAME"
            --set "clock.pop.tz$z" icon.drawing=off
                label="$(printf '%-5s %s' "${zn%%|*}" "$zt")"
                label.font="$F_MONO" label.color="$C_TEXT" label.align=left width="$PW" label.padding_left="$PL"
                background.drawing=on background.color=0x00000000 background.height="$H_ROW")
        z=$((z + 1))
    done

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

# Routine: refresh the label; show a running-meeting glyph and a bold task badge
# (glyph + count) in the icon slot, divided from the date by a separator.
running="$(icalBuddy -nc -b "" eventsNow 2>/dev/null | grep -c .)"
tcount="$(icalBuddy -nc -b "" "tasksDueBefore:$(date -v+3m '+%Y-%m-%d')" 2>/dev/null | grep -c '^[^[:space:]]')"
date_s="$(date '+%a %b %-d %H:%M')"
icon=""; icol="$C_GREEN"
[ "${running:-0}" -gt 0 ] 2>/dev/null && icon="$G_MEET"
if [ "${tcount:-0}" -gt 0 ] 2>/dev/null; then
    [ -n "$icon" ] && icon="$icon  "
    icon="$icon$G_TASK $tcount"
    [ "${running:-0}" -gt 0 ] 2>/dev/null || icol="$WARN" # peach when tasks only
fi
if [ -n "$icon" ]; then
    sketchybar --set "$NAME" icon="$icon" icon.font="MesloLGS Nerd Font:Regular:14.0" icon.color="$icol" icon.padding_left=8 icon.drawing=on label="│ $date_s"
else
    sketchybar --set "$NAME" icon.drawing=off label="$date_s"
fi
