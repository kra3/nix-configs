#!/run/current-system/sw/bin/bash
source "${0%/*}/../theme.sh"
# System volume: speaker glyph + %. Popup (click) has a draggable slider +
# output-device list.
#   volume.sh          → routine/volume_change: refresh icon + slider
#   volume.sh toggle   → click: toggle popup (right-click opens Sound prefs)
#   volume.sh slider   → mouse.clicked on the slider: set volume to $PERCENTAGE
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

set_icon() {
    local vol muted icon color
    vol="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
    muted="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)"
    if [ "$muted" = "true" ] || [ "$vol" = "0" ]; then
        icon="󰝟"; color="$DISABLED"
    elif [ "$vol" -lt 34 ]; then
        icon="󰕿"; color="$BAR_TEXT"
    elif [ "$vol" -lt 67 ]; then
        icon="󰖀"; color="$BAR_TEXT"
    else
        icon="󰕾"; color="$BAR_TEXT"
    fi
    sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="${vol}%"
    sketchybar --set volume.slider slider.percentage="${vol:-0}" 2>/dev/null
}

populate_devices() {
    command -v SwitchAudioSource >/dev/null 2>&1 || { sketchybar --remove '/volume\.dev\..*/' 2>/dev/null; return 0; }
    local cur key mark col dev
    # One sketchybar call for the whole device list.
    local VOL_ARGS=(--remove '/volume\.dev\..*/'
        --add item volume.dev.hdr popup."$NAME"
        --set volume.dev.hdr icon.drawing=off label="Output"
            label.font="Helvetica Neue:Bold:13.0" label.color="$POPUP_HEAD" label.align=left
            width=220 label.padding_left=10
            background.drawing=on background.color="$HEADER_BG" background.height=20 background.corner_radius=4)
    cur="$(SwitchAudioSource -c -t output 2>/dev/null)"
    while IFS= read -r dev; do
        [ -n "$dev" ] || continue
        key="$(printf '%s' "$dev" | tr -c 'A-Za-z0-9' '_')"
        if [ "$dev" = "$cur" ]; then mark="󰄬"; col="$OK"; else mark=""; col="$POPUP_DIM"; fi
        VOL_ARGS+=(--add item "volume.dev.$key" popup."$NAME"
            --set "volume.dev.$key" icon="$mark" icon.color="$OK" icon.font="MesloLGS Nerd Font:Bold:12.0"
                label="$dev" label.color="$col" label.font="Helvetica Neue:Regular:13.0" label.max_chars=24
                label.align=left width=220 label.padding_left=4
                background.drawing=on background.color=0x00000000 background.height=22
                click_script="SwitchAudioSource -s \"$dev\" >/dev/null 2>&1; $CONFIG_DIR/plugins/volume.sh; sketchybar --set $NAME popup.drawing=off")
    done < <(SwitchAudioSource -a -t output 2>/dev/null)
    sketchybar "${VOL_ARGS[@]}"
}

# Pointer left the item and its popup → dismiss (auto-close on focus loss).
if [ "$SENDER" = "mouse.exited.global" ]; then
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
fi

case "$1" in
    slider)
        # Only set volume on a real drag ($PERCENTAGE set), not on forced refresh.
        [ -n "$PERCENTAGE" ] && osascript -e "set volume output volume $PERCENTAGE" 2>/dev/null
        vol="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
        sketchybar --set volume.slider slider.percentage="${vol:-0}"
        exit 0
        ;;
    toggle)
        # Right-click → open the Sound preference pane instead of the popup.
        if [ "$BUTTON" = "right" ]; then
            open /System/Library/PreferencePanes/Sound.prefPane
            exit 0
        fi
        if [ "$(sketchybar --query "$NAME" 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)" = "on" ]; then
            sketchybar --set "$NAME" popup.drawing=off
        else
            populate_devices
            sketchybar --set "$NAME" popup.drawing=on
        fi
        exit 0
        ;;
esac

set_icon
