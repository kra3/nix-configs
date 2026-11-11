# Two-way git sync of one second-brain vault with its hub repo, run every few minutes
# (sutala: systemd timer; Macs: launchd agent).
# Env: VAULT_DIR, VAULT_GIT_DIR, REMOTE, SYNC_HOST, optional OBSIDIAN_MANAGED (see below); on sutala a deploy key via
# $CREDENTIALS_DIRECTORY/deploy-key, elsewhere the user's own ssh setup.
# The git dir lives outside the vault, so nothing in the vault itself is git machinery.
# Remote unreachable (offline, VPN down): local changes are still committed, the run exits 75
# (EX_TEMPFAIL) and the next run catches up.
# On a rebase conflict, this host's commits go to a conflict/<host>-<time> branch (nothing is
# lost), the vault resets to the hub's main, and the run exits 1 so the failure is visible.

export GIT_DIR="$VAULT_GIT_DIR" GIT_WORK_TREE="$VAULT_DIR"
g() { git -c user.name=second-brain -c "user.email=second-brain@$SYNC_HOST" -c core.quotepath=off "$@"; }
offline() {
  echo "remote unreachable ($1); local changes are committed, will retry next run" >&2
  exit 75
}

if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/deploy-key" ]; then
  export GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/deploy-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
fi

mkdir -p "$VAULT_DIR"
if [ ! -e "$GIT_DIR/HEAD" ]; then
  g init --quiet --initial-branch=main
  g remote add origin "$REMOTE"
fi
g remote set-url origin "$REMOTE"

has_remote_main() { g rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; }
has_head() { g rev-parse --verify --quiet HEAD >/dev/null; }

if ! has_head; then
  # First sync decides the history, so it needs the hub: never start a second root offline.
  g fetch --quiet origin || offline "first sync"
  if has_remote_main; then
    # Adopt the hub's history, but only into an empty vault: a checkout over existing files
    # would silently pick one side.
    if [ -n "$(find "$VAULT_DIR" -mindepth 1 -maxdepth 1 ! -name .gitignore -print -quit)" ]; then
      echo "refusing first sync: $VAULT_DIR is not empty and $REMOTE already has history; move the files out, rerun, then move them back in" >&2
      exit 1
    fi
    g checkout --quiet --force -B main origin/main
  fi
fi

# Shared ignore rules, committed so every clone uses them.
if [ ! -e "$VAULT_DIR/.gitignore" ]; then
  printf '%s\n' '.obsidian/workspace*.json' '.obsidian/cache' '.trash/' '.mcp-*.tmp' '.DS_Store' '.obsidian/plugins/obsidian-git/data.json' >"$VAULT_DIR/.gitignore"
fi

# Obsidian settings declared in Nix (a brain's `obsidian` option): OBSIDIAN_MANAGED is a store path
# with settings/<file>.json, themes/<name>/ and plugins/<id>/. Managed keys win and the rest of
# the vault's .obsidian stays as is; the changes are then committed and synced like any edit.
if [ -n "${OBSIDIAN_MANAGED:-}" ]; then
  obs="$VAULT_DIR/.obsidian"
  mkdir -p "$obs"
  while IFS= read -r -d '' frag; do
    rel="${frag#"$OBSIDIAN_MANAGED"/settings/}"
    dest="$obs/$rel"
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "$dest.XXXXXX")"
    if [ -s "$dest" ] && jq -e . "$dest" >/dev/null 2>&1; then
      # Arrays (community-plugins) are unioned; objects merge with managed keys winning.
      jq -s '.[0] as $a | .[1] as $b
             | if ($a|type) == "array" and ($b|type) == "array" then ($a + $b | unique)
               elif ($a|type) == "object" and ($b|type) == "object" then $a * $b
               else $b end' "$dest" "$frag" >"$tmp"
    else
      jq . "$frag" >"$tmp"
    fi
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then rm -f "$tmp"; else chmod 664 "$tmp"; mv "$tmp" "$dest"; fi
  done < <(find -L "$OBSIDIAN_MANAGED/settings" -type f -name '*.json' -print0 2>/dev/null)
  for kind in themes plugins; do
    for src in "$OBSIDIAN_MANAGED/$kind"/*; do
      [ -e "$src" ] || continue
      dest="$obs/$kind/$(basename "$src")"
      if ! diff -rq "$src/" "$dest/" >/dev/null 2>&1; then
        mkdir -p "$dest"
        cp -rL --no-preserve=mode,ownership "$src/." "$dest/"
      fi
    done
  done
fi

g add --all
if ! g diff --cached --quiet; then
  g commit --quiet -m "$SYNC_HOST: $(date --iso-8601=minutes)"
fi

g fetch --quiet origin || offline "fetch"

if has_remote_main && has_head && ! g rebase --quiet origin/main; then
  g rebase --abort || true
  branch="conflict/$SYNC_HOST-$(date +%Y%m%d-%H%M%S)"
  g push --quiet origin "HEAD:refs/heads/$branch" || offline "pushing $branch"
  g reset --quiet --hard origin/main
  echo "conflict with origin/main: this host's commits are on $branch (merge it on a machine with the vault); vault reset to origin/main" >&2
  exit 1
fi

if has_head; then
  g push --quiet origin HEAD:main || offline "push"
fi
