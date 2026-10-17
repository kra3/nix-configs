#!/usr/bin/env bash
# Remove worktrees + local branches whose PR is merged/closed, tip == PR head, tree clean, no process inside.
set -u
primary=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
primary=${primary%/.git}
cd "$primary" || exit 0
here=$(git rev-parse --show-toplevel 2>/dev/null)

git worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} /^branch /{print p "\t" substr($0,19)}' |
while IFS=$'\t' read -r path branch; do
  [ "$path" = "$primary" ] && continue
  [ "$path" = "$here" ] && continue
  [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ] && continue
  tip=$(git -C "$path" rev-parse HEAD) || continue
  pr=$(gh pr list --head "$branch" --state all --json state,headRefOid --jq '.[0] | select(.state != "OPEN") | .headRefOid' 2>/dev/null)
  [ "$pr" = "$tip" ] || continue
  for c in /proc/[0-9]*/cwd; do
    case "$(readlink "$c" 2>/dev/null)" in "$path"|"$path"/*) continue 2 ;; esac
  done
  if [ -n "${DRY_RUN:-}" ]; then echo "would prune $path ($branch)"; continue; fi
  git worktree remove "$path" && git branch -D "$branch" >/dev/null && echo "pruned worktree $path ($branch)"
done
exit 0
