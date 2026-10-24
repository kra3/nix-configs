#!/usr/bin/env bash
# Block pushes and PRs until reviews ran for the commits since the last review (see CLAUDE.md "Skills at each step").
in=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$in")
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
cwd=$(jq -r '.cwd // ""' <<<"$in")
[[ ${CLAUDE_SKIP_REVIEW_GATE:-0} == 1 ]] && exit 0
block() { printf 'review-gate: %s\n' "$1" >&2; exit 2; }

case $tool in
  mcp__github__push_files | mcp__github__create_or_update_file)
    block "push through local git (git push) so the review gate can check the change." ;;
  mcp__github__create_pull_request) ;;
  Bash)
    [[ $cmd =~ git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$) || $cmd =~ gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0 ;;
  *) exit 0 ;;
esac

dir=$cwd
if [[ $cmd =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  dir=${BASH_REMATCH[1]}
elif [[ $cmd =~ (^|[;&|])[[:space:]]*cd[[:space:]]+([^[:space:];\&|]+) ]]; then
  dir=${BASH_REMATCH[2]}
fi
dir=${dir//[\"\']/}
dir=${dir/#\~/$HOME}
[[ $dir == /* ]] || dir=$cwd/$dir
[[ $dir == *'$'* || ! -d $dir ]] && dir=$cwd
g() { git -C "$dir" "$@" 2>/dev/null; }

head=$(g rev-parse HEAD) || exit 0
gitdir=$(g rev-parse --path-format=absolute --git-common-dir)
mark() { echo "$gitdir/review-ok-$1"; }
[[ -e $(mark "$head") ]] && exit 0

main=""
for remote in $(g remote); do
  for ref in "$remote/HEAD" "$remote/main" "$remote/master"; do main=$(g merge-base HEAD "$ref") && break 2; done
done
[[ -n $main ]] || block "no remote default branch to compare against; review, then: touch $(mark "$head")"

base=$main
trailers=1
for c in $(g rev-list "$main..HEAD"); do
  [[ -e $(mark "$c") ]] && { base=$c; break; }
  g log -1 --format=%B "$c" | grep -qi '^Review: skip' || trailers=0
done

files=$(g diff --name-only "$base" HEAD)
[[ -n $files ]] || exit 0
lines=$(g diff --numstat "$base" HEAD | awk '{n += $1 + $2} END {print n + 0}')

defaults='auth|security|secret|credential|crypt|permission|payment|billing|migrat|deploy|infra|firewall|sops|(^|/)\.env|\.github/workflows/|dockerfile|\.tf$|helm|k8s|kubernetes|(^|/)\.claude/review-gate\.paths$'
rules=()
while IFS= read -r l; do
  [[ -z ${l//[[:space:]]/} || $l == \#* ]] || rules+=("$l")
done < <(g show "$main:.claude/review-gate.paths")

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

todo="run ponytail:ponytail-review, code-review and superpowers:verification-before-completion on ${base:0:7}..HEAD, then: touch $(mark "$head")"
((${#reasons[@]})) && block "high-impact change ($(IFS=';'; echo "${reasons[*]}")); $todo. Only the user can skip this (CLAUDE_SKIP_REVIEW_GATE=1)."
((lines <= 20 || trailers)) && exit 0
block "$lines changed lines since ${base:0:7}; $todo. For trivial commits add a \"Review: skip\" trailer to each one instead."
