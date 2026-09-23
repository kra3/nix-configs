#!/run/current-system/sw/bin/bash
source "${0%/*}/../theme.sh"
# Link type + VPN glyph. Left-click → SSID/IP/Subnet/Router popup (click-to-copy);
# right-click → Network prefs. Wi-Fi detected by device active (not utun route).
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
PW=240

WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/ { getline; print $2; exit }')"

# Active interface: Wi-Fi if up, else the default route's interface.
if [ -n "$WIFI_DEV" ] && ifconfig "$WIFI_DEV" 2>/dev/null | grep -q 'status: active'; then
    IFACE="$WIFI_DEV"
else
    IFACE="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')"
fi

# Pointer left the item and its popup → dismiss.
if [ "$SENDER" = "mouse.exited.global" ]; then
    sketchybar --set "$NAME" popup.drawing=off
    exit 0
fi

build_popup() {
    local ssid ip mask router half k v kv
    ssid="$(networksetup -getairportnetwork "$WIFI_DEV" 2>/dev/null | sed 's/^Current Wi-Fi Network: //')"
    case "$ssid" in "" | *"not associated"* | *"not currently"* | *"off"*) ssid="—" ;; esac
    ip="$(ipconfig getifaddr "$IFACE" 2>/dev/null)"; ip="${ip:-—}"
    mask="$(ipconfig getoption "$IFACE" subnet_mask 2>/dev/null)"; mask="${mask:-—}"
    router="$(ipconfig getoption "$IFACE" router 2>/dev/null)"; router="${router:-—}"
    half=$((PW / 2))
    # Two-column rows (icon=key left / label=value right) built in one call.
    local A=(--remove '/network\.pop\..*/'
        --add item network.pop.hdr popup."$NAME"
        --set network.pop.hdr icon="󰖩" icon.color="$SECONDARY" icon.font="MesloLGS Nerd Font:Bold:13.0"
            label="$ssid" label.color="$POPUP_HEAD" label.font="Helvetica Neue:Bold:13.0" label.align=left
            label.max_chars=24 width="$PW" label.padding_left=6
            background.drawing=on background.color="$HEADER_BG" background.height=20 background.corner_radius=4)
    for kv in "IP|$ip" "Subnet|$mask" "Router|$router"; do
        k="${kv%%|*}"; v="${kv#*|}"
        A+=(--add item "network.pop.$k" popup."$NAME"
            --set "network.pop.$k"
                icon="$k" icon.font="Helvetica Neue:Regular:12.0" icon.color="$POPUP_DIM"
                icon.align=left icon.width="$half" icon.padding_left=12
                label="$v" label.font="Menlo:Regular:12.0" label.color="$POPUP_TEXT"
                label.align=right label.width="$half" label.padding_right=12
                background.drawing=on background.color=0x00000000 background.height=22
                click_script="printf '%s' \"\$(sketchybar --query network.pop.$k | jq -r .label.value)\" | pbcopy; sketchybar --set network.pop.$k label.color="$OK"; (sleep 0.8; sketchybar --set network.pop.$k label.color="$POPUP_TEXT") &")
    done
    sketchybar "${A[@]}"
}

if [ "$1" = "toggle" ]; then
    if [ "$BUTTON" = "right" ]; then
        open /System/Library/PreferencePanes/Network.prefPane
        exit 0
    fi
    if [ "$(sketchybar --query "$NAME" 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)" = "on" ]; then
        sketchybar --set "$NAME" popup.drawing=off
    else
        build_popup
        sketchybar --set "$NAME" popup.drawing=on
    fi
    exit 0
fi

# Routine: link icon + VPN glyph.
if [ -n "$WIFI_DEV" ] && [ "$IFACE" = "$WIFI_DEV" ]; then
    ICON="󰖩" # wifi
    COLOR="$BAR_TEXT"
elif [ -n "$IFACE" ]; then
    ICON="󰈀" # wired (some default route, Wi-Fi not active)
    COLOR="$BAR_TEXT"
else
    ICON="󰤭" # offline
    COLOR="$CRIT"
fi

if scutil --nc list 2>/dev/null | grep -q "(Connected)"; then
    VPN="󰦝"
    VPNCOLOR="$OK"
else
    VPN=""
    VPNCOLOR="$COLOR"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$VPN" label.color="$VPNCOLOR"
