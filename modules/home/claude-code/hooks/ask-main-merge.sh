#!/usr/bin/env bash
# Ask for human approval when a commit/merge/PR-merge targets main or master.
in=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$in")
cwd=$(jq -r '.cwd // ""' <<<"$in")

ask() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

is_main() { [[ $1 == main || $1 == master ]]; }

base_of_pr() { # num [repo] -> base branch, empty on failure
  if [[ -n $2 ]]; then
    gh pr view "$1" --repo "$2" --json baseRefName -q .baseRefName 2>/dev/null
  else
    (cd "$cwd" 2>/dev/null && gh pr view "$1" --json baseRefName -q .baseRefName 2>/dev/null)
  fi
}

if [[ $tool == mcp__github__merge_pull_request ]]; then
  owner=$(jq -r '.tool_input.owner' <<<"$in")
  repo=$(jq -r '.tool_input.repo' <<<"$in")
  num=$(jq -r '.tool_input.pullNumber' <<<"$in")
  base=$(base_of_pr "$num" "$owner/$repo")
  if [[ -z $base ]] || is_main "$base"; then
    ask "Merging PR #$num into '${base:-unknown base}' needs explicit human approval."
  fi
  exit 0
fi

[[ $tool == Bash ]] || exit 0
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")

# directory the git command will run in: git -C X, else leading "cd X", else session cwd
dir=$cwd
if [[ $cmd =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  dir=${BASH_REMATCH[1]}
elif [[ $cmd =~ (^|[;&|[:space:]])cd[[:space:]]+([^[:space:];\&|]+) ]]; then
  dir=${BASH_REMATCH[2]}
fi
dir=${dir/#\~/$HOME}

branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null)

if [[ $cmd =~ git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+(commit|merge)([[:space:]]|$) ]]; then
  verb=${BASH_REMATCH[3]}
  if [[ -z $branch ]] || is_main "$branch"; then
    ask "git $verb on '${branch:-unknown/detached HEAD}' needs explicit human approval."
  fi
fi

if [[ $cmd =~ gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) ]]; then
  rest=${cmd#*pr merge}
  num=""
  repo=""
  for t in $rest; do
    case $t in
      --repo=*) repo=${t#--repo=} ;;
      -R | --repo) next_is_repo=1 ;;
      -*) ;;
      *) if [[ -n $next_is_repo ]]; then repo=$t; next_is_repo=""; elif [[ -z $num ]]; then num=$t; fi ;;
    esac
  done
  [[ $num == http* ]] && num=${num##*/}
  base=$(base_of_pr "${num:-}" "$repo")
  if [[ -z $base ]] || is_main "$base"; then
    ask "Merging PR ${num:-for current branch} into '${base:-unknown base}' needs explicit human approval."
  fi
fi
exit 0
