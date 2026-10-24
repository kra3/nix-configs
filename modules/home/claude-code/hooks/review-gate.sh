#!/usr/bin/env bash
# git pre-push hook (hook.review-gate): blocks Claude Code's pushes until the new commits were reviewed (see CLAUDE.md "Skills at each step").
[[ ${CLAUDECODE:-} == 1 && ${CLAUDE_SKIP_REVIEW_GATE:-0} != 1 ]] || exit 0
remote=$1
gitdir=$(git rev-parse --path-format=absolute --git-common-dir)
mark() { echo "$gitdir/review-ok-$1"; }
defaults='auth|security|secret|credential|crypt|permission|payment|billing|migrat|deploy|infra|firewall|sops|(^|/)\.env|\.github/workflows/|dockerfile|\.tf$|helm|k8s|kubernetes|(^|/)\.claude/review-gate\.paths$'

tip=""
for ref in "$remote/HEAD" "$remote/main" "$remote/master"; do tip=$(git rev-parse -q --verify "$ref^{commit}") && break; done
rules=()
if [[ -n $tip ]]; then
  while IFS= read -r l; do
    [[ -z ${l//[[:space:]]/} || $l == \#* ]] || rules+=("$l")
  done < <(git show "$tip:.claude/review-gate.paths" 2>/dev/null)
fi

check() { # local_sha base -> exit 2 with a message when the range needs review
  local head=$1 base=$2 c parents body trailers=1 lines files deleted risky f r hit todo reasons=()
  [[ -e $(mark "$head") ]] && return 0
  while IFS= read -r -d "" c && IFS= read -r -d "" parents && IFS= read -r -d "" body; do
    c=${c#$'\n'}
    [[ -e $(mark "$c") ]] && { base=$c; break; }
    [[ $parents == *" "* ]] || grep -qi '^Review: skip' <<<"$body" || trailers=0
  done < <(git log --format='%H%x00%P%x00%B%x00' "$base..$head")
  files=$(git diff --name-only "$base" "$head")
  [[ -n $files ]] || return 0
  shopt -s nocasematch
  lines=$(git diff --numstat "$base" "$head" | awk '{n += $1 + $2} END {print n + 0}')
  while IFS= read -r f; do
    hit=0
    [[ $f =~ $defaults ]] && hit=1
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
  deleted=$(git diff --diff-filter=D --name-only "$base" "$head")
  [[ -n $deleted ]] && reasons+=("deletes: ${deleted//$'\n'/, }")
  risky=$(git diff -U0 "$base" "$head" -- . ':!*.md' | grep -E '^\+[^+]' | grep -E -o 'DROP[[:space:]]+(TABLE|DATABASE)|TRUNCATE|rm -rf|chmod|sudo |--force|eval\(' | sort -u | paste -sd, -)
  [[ -n $risky ]] && reasons+=("diff adds: $risky")
  todo="run ponytail:ponytail-review, code-review and superpowers:verification-before-completion on ${base:0:7}..${head:0:7}, then: touch $(mark "$head")"
  if ((${#reasons[@]})); then
    echo "review-gate: high-impact change ($(IFS=';'; echo "${reasons[*]}")); $todo. Only the user can skip this (CLAUDE_SKIP_REVIEW_GATE=1)." >&2
    return 2
  fi
  ((lines <= 20 || trailers)) && return 0
  echo "review-gate: $lines changed lines since ${base:0:7}; $todo. For trivial commits add a \"Review: skip\" trailer to each one instead." >&2
  return 2
}

status=0
while read -r _ lsha _ rsha; do
  [[ $lsha =~ ^0+$ ]] && continue
  if [[ ! $rsha =~ ^0+$ ]] && git cat-file -e "$rsha^{commit}" 2>/dev/null; then
    base=$(git merge-base "$rsha" "$lsha")
  elif [[ -n $tip ]]; then
    base=$(git merge-base "$tip" "$lsha")
  else
    [[ -e $(mark "$lsha") ]] || { echo "review-gate: no $remote/HEAD, main or master to compare against; review, then: touch $(mark "$lsha")" >&2; status=2; }
    continue
  fi
  check "$lsha" "$base" || status=2
done
exit $status
