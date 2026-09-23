#!/usr/bin/env bash
# Focused app name. $INFO is set by front_app_switched; on first load it's empty,
# so fall back to querying AeroSpace's focused window.
APP="$INFO"
if [ -z "$APP" ]; then
    APP="$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null | head -1)"
fi
sketchybar --set "$NAME" label="$APP"
