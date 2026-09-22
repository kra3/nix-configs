#!/usr/bin/env bash
# Link type + VPN glyph.
#   icon  = Wi-Fi / wired / offline  (detected by the Wi-Fi device being active,
#           so a VPN tunnel's utun default route isn't mistaken for wired)
#   label = VPN shield when any NC connection is up

WIFI_DEV="$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/ { getline; print $2; exit }')"

if [ -n "$WIFI_DEV" ] && ifconfig "$WIFI_DEV" 2>/dev/null | grep -q 'status: active'; then
    ICON="󰖩" # wifi
    COLOR=0xffcdd6f4
elif route -n get default 2>/dev/null | grep -q 'interface:'; then
    ICON="󰈀" # wired (some default route, Wi-Fi not active)
    COLOR=0xffcdd6f4
else
    ICON="󰤭" # offline
    COLOR=0xfff38ba8
fi

if scutil --nc list 2>/dev/null | grep -q "(Connected)"; then
    VPN="󰦝"
    VPNCOLOR=0xffa6e3a1
else
    VPN=""
    VPNCOLOR="$COLOR"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$VPN" label.color="$VPNCOLOR"
