#!/usr/bin/env bash
# Block git push / gh pr create until reviews ran for HEAD (see CLAUDE.md "Skills at each step").
in=$(cat)
[[ $(jq -r '.tool_name // ""' <<<"$in") == Bash ]] || exit 0
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
cwd=$(jq -r '.cwd // ""' <<<"$in")
[[ $cmd =~ git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$) || $cmd =~ gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0
[[ ${CLAUDE_SKIP_REVIEW_GATE:-0} == 1 ]] && exit 0

dir=$cwd
if [[ $cmd =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  dir=${BASH_REMATCH[1]}
elif [[ $cmd =~ (^|[;&|[:space:]])cd[[:space:]]+([^[:space:];\&|]+) ]]; then
  dir=${BASH_REMATCH[2]}
fi
dir=${dir/#\~/$HOME}
g() { git -C "$dir" "$@" 2>/dev/null; }

head=$(g rev-parse HEAD) || exit 0
marker="$(cd "$dir" && realpath "$(git rev-parse --git-common-dir)")/review-ok-$head"
[[ -e $marker ]] && exit 0
base=""
for ref in origin/HEAD origin/main origin/master; do base=$(g merge-base HEAD "$ref") && break; done
[[ -n $base ]] || exit 0

files=$(g diff --name-only "$base" HEAD)
[[ -n $files ]] || exit 0
lines=$(g diff --numstat "$base" HEAD | awk '{n += $1 + $2} END {print n + 0}')

defaults='auth|security|secret|credential|crypt|permission|payment|billing|migrat|deploy|infra|firewall|sops|(^|/)\.env|\.github/workflows/|dockerfile|\.tf$|helm|k8s|kubernetes|(^|/)\.claude/review-gate\.paths$'
rules=()
listfile="$(g rev-parse --show-toplevel)/.claude/review-gate.paths"
[[ -f $listfile ]] && mapfile -t rules < <(grep -v -e '^#' -e '^[[:space:]]*$' "$listfile")

reasons=()
while IFS= read -r f; do
  hit=0
  shopt -s nocasematch
  [[ $f =~ $defaults ]] && hit=1
  shopt -u nocasematch
  for r in "${rules[@]}"; do
    if [[ $r == !* ]]; then
      # shellcheck disable=SC2053
      [[ $f == ${r#!} ]] && hit=0
    else
      # shellcheck disable=SC2053
      [[ $f == $r ]] && hit=1
    fi
  done
  ((hit)) && reasons+=("$f")
done <<<"$files"
deleted=$(g diff --diff-filter=D --name-only "$base" HEAD)
[[ -n $deleted ]] && reasons+=("deletes: ${deleted//$'\n'/, }")
risky=$(g diff -U0 "$base" HEAD | grep -E '^\+[^+]' | grep -E -o 'DROP[[:space:]]+(TABLE|DATABASE)|TRUNCATE|rm -rf|chmod|sudo |--force|eval\(' | sort -u | paste -sd, -)
[[ -n $risky ]] && reasons+=("diff adds: $risky")

if ((${#reasons[@]})); then
  printf 'review-gate: high-impact change (%s).\nRun code-review and superpowers:verification-before-completion, then: touch %s\nOnly the user can skip this (CLAUDE_SKIP_REVIEW_GATE=1).\n' "$(IFS=';'; echo "${reasons[*]}")" "$marker" >&2
  exit 2
fi
((lines <= 20)) && exit 0
g log -1 --format=%B HEAD | grep -qi '^Review: skip' && exit 0
printf 'review-gate: %s changed lines since %s.\nRun ponytail:ponytail-review, code-review and superpowers:verification-before-completion, then: touch %s\nTrivial follow-up: add a "Review: skip" trailer to the commit instead.\n' "$lines" "${base:0:7}" "$marker" >&2
exit 2
