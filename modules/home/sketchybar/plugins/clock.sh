#!/usr/bin/env bash
# 24-hour time. %-d omits the leading zero on the day.
sketchybar --set "$NAME" label="$(date '+%a %b %-d %H:%M')"
