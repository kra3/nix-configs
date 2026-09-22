#!/usr/bin/env bash
# Link type + VPN state as glyphs.
#   icon  = active link: Wi-Fi / Ethernet / offline
#   label = VPN shield when any connection is up (empty otherwise)

IFACE="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')"

if [ -z "$IFACE" ]; then
    ICON="󰤭" # offline
    COLOR=0xfff38ba8
else
    PORT="$(networksetup -listallhardwareports 2>/dev/null \
        | awk -v d="$IFACE" '/Hardware Port:/ { p = substr($0, 16) } /Device:/ { if ($2 == d) print p }')"
    case "$PORT" in
        *Wi-Fi* | *AirPort*) ICON="󰖩" ;;
        *) ICON="󰈀" ;; # ethernet / USB-LAN / thunderbolt bridge
    esac
    COLOR=0xffcdd6f4
fi

if scutil --nc list 2>/dev/null | grep -q "(Connected)"; then
    VPN="󰦝"
    VPNCOLOR=0xffa6e3a1
else
    VPN=""
    VPNCOLOR="$COLOR"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$VPN" label.color="$VPNCOLOR"
