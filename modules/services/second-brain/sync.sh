# Two-way git sync of the second-brain vault with its hub repo (run by second-brain-sync.timer).
# Env: VAULT_DIR, VAULT_GIT_DIR, REMOTE, SYNC_HOST; deploy key via $CREDENTIALS_DIRECTORY/deploy-key.
# The git dir lives outside the vault, so nothing in the vault itself is git machinery.
# On a rebase conflict, sutala's commits go to a conflict/<host>-<time> branch (nothing is lost),
# the vault resets to the hub's main, and the run exits non-zero so the failure shows in Loki.

export GIT_DIR="$VAULT_GIT_DIR" GIT_WORK_TREE="$VAULT_DIR"
g() { git -c user.name=second-brain -c "user.email=second-brain@$SYNC_HOST" -c core.quotepath=off "$@"; }

if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/deploy-key" ]; then
  export GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/deploy-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
fi

if [ ! -e "$GIT_DIR/HEAD" ]; then
  g init --quiet --initial-branch=main
  g remote add origin "$REMOTE"
fi
g remote set-url origin "$REMOTE"

g fetch --quiet origin
has_remote_main() { g rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; }
has_head() { g rev-parse --verify --quiet HEAD >/dev/null; }

if ! has_head && has_remote_main; then
  # First run against a hub that already has notes: adopt its history. Only into an empty vault,
  # since a checkout over existing files would silently pick one side.
  if [ -n "$(find "$VAULT_DIR" -mindepth 1 -maxdepth 1 ! -name .gitignore -print -quit)" ]; then
    echo "refusing first sync: $VAULT_DIR is not empty and $REMOTE already has history; empty the server vault (it is only a copy) and rerun" >&2
    exit 1
  fi
  g checkout --quiet --force -B main origin/main
fi

# Shared ignore rules, committed so every clone (the Mac included) uses them.
if [ ! -e "$VAULT_DIR/.gitignore" ]; then
  printf '%s\n' '.obsidian/workspace*.json' '.obsidian/cache' '.trash/' '.mcp-*.tmp' '.DS_Store' >"$VAULT_DIR/.gitignore"
fi

g add --all
if ! g diff --cached --quiet; then
  g commit --quiet -m "$SYNC_HOST: $(date --iso-8601=minutes)"
fi

if has_remote_main && ! g rebase --quiet origin/main; then
  g rebase --abort || true
  branch="conflict/$SYNC_HOST-$(date +%Y%m%d-%H%M%S)"
  g push --quiet origin "HEAD:refs/heads/$branch"
  g reset --quiet --hard origin/main
  echo "conflict with origin/main: sutala's commits are on $branch (merge it on the Mac); vault reset to origin/main" >&2
  exit 1
fi

if has_head; then
  g push --quiet origin HEAD:main
fi
