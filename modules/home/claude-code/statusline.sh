#!/usr/bin/env bash
# Claude Code statusLine command (user scope, ~/.claude/settings.json).
#
# Renders, left to right:
#   1. directory/repo name + git branch (dim cyan)
#   2. active model display name (dim magenta)
#   3. context window usage percentage, if available (dim yellow)
#
# Reads the statusLine JSON payload on stdin. Only depends on jq, git and
# POSIX-ish shell builtins so it runs unmodified on NixOS and other boxes.

input="$(cat)"

cwd="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

model="$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)"
used_pct="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)"

# --- 1. directory/repo name + branch -----------------------------------
dir_label="$(basename "$cwd")"
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  toplevel="$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$toplevel" ] && dir_label="$(basename "$toplevel")"
  branch="$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)"
  if [ -z "$branch" ]; then
    branch="$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
  fi
  gs="$(git -C "$cwd" --no-optional-locks status --porcelain=v2 -b 2>/dev/null)"
  printf '%s\n' "$gs" | grep -q '^[12?u] ' && branch="${branch}*"
  read -r ahead behind <<<"$(printf '%s\n' "$gs" | sed -n 's/^# branch.ab +\([0-9]*\) -\([0-9]*\)$/\1 \2/p')"
  [ "${ahead:-0}" -gt 0 ] && branch="${branch} ↑${ahead}"
  [ "${behind:-0}" -gt 0 ] && branch="${branch} ↓${behind}"
fi

# --- colors (dim, since the status line is already rendered dim) -------
c_dim=$'\033[2m'
c_cyan=$'\033[2;36m'
c_magenta=$'\033[2;35m'
c_yellow=$'\033[2;33m'
c_reset=$'\033[0m'

segments=()

loc_seg="${c_cyan}${dir_label}${c_reset}"
[ -n "$branch" ] && loc_seg="${loc_seg}${c_dim} (${branch})${c_reset}"
segments+=("$loc_seg")

[ -n "$model" ] && segments+=("${c_magenta}${model}${c_reset}")

IFS='|' read -r style cost h5 h5_reset d7 d7_reset <<<"$(printf '%s' "$input" | jq -r '[.output_style.name // "", .cost.total_cost_usd // "", .rate_limits.five_hour.used_percentage // "", .rate_limits.five_hour.resets_at // "", .rate_limits.seven_day.used_percentage // "", .rate_limits.seven_day.resets_at // ""] | map(tostring) | join("|")' 2>/dev/null)"

c_red=$'\033[31m'
now="$(date +%s)"
limit_seg() {
  local label="$1" used rem=-1 pace=0 col="$c_dim" txt
  used="$(printf '%.0f' "$2")"
  [ -n "$3" ] && rem=$(( $3 - now ))
  [ "$rem" -gt 0 ] && [ "$rem" -lt "$4" ] && pace=$(( ($4 - rem) * 100 / $4 ))
  if [ "$pace" -ge 10 ]; then
    if [ "$used" -gt "$pace" ]; then col="$c_red"
    elif [ $(( used * 100 )) -gt $(( pace * 80 )) ]; then col="$c_yellow"; fi
  elif [ "$used" -ge 70 ]; then col="$c_yellow"
  fi
  [ "$used" -ge 90 ] && col="$c_red"
  txt="${label} ${used}%"
  [ "$col" != "$c_dim" ] && [ "$5" = reset ] && [ "$rem" -gt 0 ] && txt="${txt} $((rem / 3600))h$(printf '%02d' $(( rem % 3600 / 60 )))m"
  printf '%s%s%s' "$col" "$txt" "$c_reset"
}

[ -n "$style" ] && [ "$style" != "default" ] && [ "$style" != "Default" ] && segments+=("${c_dim}${style}${c_reset}")

if [ -n "$used_pct" ]; then
  used_pct_r="$(printf '%.0f' "$used_pct" 2>/dev/null)"
  [ -n "$used_pct_r" ] && segments+=("${c_yellow}ctx ${used_pct_r}%${c_reset}")
fi

lim=""
[ -n "$h5" ] && lim="$(limit_seg 5h "$h5" "$h5_reset" 18000 reset)"
[ -n "$d7" ] && lim="${lim:+$lim }$(limit_seg 7d "$d7" "$d7_reset" 604800)"
[ -n "$lim" ] && segments+=("$lim")

money=""
[ -n "$cost" ] && money="${c_dim}↑ $(printf '$%.2f' "$cost")${c_reset}"

FRUGAL_SCRIPT=$(ls -d "$HOME"/.claude/plugins/cache/*/frugal/*/scripts/statusline.py \
  "$HOME"/.claude/plugins/synced/*/*/scripts/statusline.py 2>/dev/null | head -1)
if [ -n "$FRUGAL_SCRIPT" ]; then
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  txt="$(python3 "$FRUGAL_SCRIPT" ${sid:+--session "$sid"} 2>/dev/null | sed -E 's/^frugal //; s/ saved$//; s|/.*||')"
  [ -n "$txt" ] && money="${money:+$money }"$'\033[38;5;114m'"↓ ${txt}${c_reset}"
fi
[ -n "$money" ] && segments+=("$money")

out=""
sep="${c_dim} | ${c_reset}"
for seg in "${segments[@]}"; do
  if [ -z "$out" ]; then
    out="$seg"
  else
    out="${out}${sep}${seg}"
  fi
done

printf '%s' "$out"
