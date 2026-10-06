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

if [ -n "$used_pct" ]; then
  used_pct_r="$(printf '%.0f' "$used_pct" 2>/dev/null)"
  [ -n "$used_pct_r" ] && segments+=("${c_yellow}ctx ${used_pct_r}%${c_reset}")
fi

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
