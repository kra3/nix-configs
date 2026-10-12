#!/usr/bin/env bash
# Desktop notification hook for Claude Code (Notification + Stop events).
# Reads the hook JSON payload on stdin, fires a notify-send popup, and
# always exits 0 so a missing/broken notifier never blocks Claude.

command -v notify-send >/dev/null 2>&1 || exit 0

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
project="$(basename "${cwd:-}" 2>/dev/null)"

case "$event" in
  Notification)
    message="$(printf '%s' "$input" | jq -r '.message // "Claude needs your input"' 2>/dev/null)"
    title="Claude Code${project:+ — $project}"
    ;;
  Stop|*)
    message="Finished responding"
    title="Claude Code${project:+ — $project}"
    ;;
esac

notify-send --app-name="Claude Code" "$title" "$message" >/dev/null 2>&1

exit 0
