# Second brain on sutala

`modules/services/second-brain/default.nix` (`flake.nixosModules.services-second-brain-default`)
keeps a copy of the Obsidian vault on sutala, in sync with the Mac through a private GitHub
repo, and gives Claude Code on sutala the vault tools. Everything is free, and nothing listens on
the network.

| Part | Where | What it does |
| --- | --- | --- |
| Sync | `second-brain-sync.timer` (every 5 min) | `sync.sh`: commits sutala's changes, rebases onto the hub's `main`, pushes. Work tree `/srv/appdata/second-brain/vault`, git dir `/srv/appdata/second-brain/vault.git` (outside the vault) |
| MCP | `~/second-brain/.mcp.json` (kra3) | Local stdio server `second-brain-mcp` (`mcp_server.py`), started by Claude Code in `~/second-brain`, directly or through Remote Control from the phone |

Sync stays off in `hosts/sutala/configuration.nix` until its deploy key exists: sops-nix rejects
a declared key that is missing from `secrets/secrets.yaml`, which would break the nightly upgrade.
The MCP part needs no secret and is on.

## Method

Two layers, with Claude doing the filing:
- **action:** PARA folders plus GTD capture, clarify and weekly review;
- **knowledge:** Zettelkasten/evergreen notes plus maps of content.

```
0 Inbox → (weekly clarify) → 1 Projects / 2 Areas  (tasks)
                           → 3 Sources → 4 Notes (evergreen, your words) → 5 Maps
projects draw on notes and maps (express); finished things → 6 Archive
```

The vault template, rules and process live in `docs/second-brain-starter/`:
- `CLAUDE.md`: folder rules, the weekly review, and the rule that Claude suggests but never writes evergreen notes;
- `Templates/`: Capture, Daily, Project, Source, Evergreen, Map.

## Devices

| Device | Role | How it reaches the vault |
| --- | --- | --- |
| Mac | Main writing | Obsidian + the Obsidian Git community plugin, auto pull/commit/push every few minutes; Claude Code in the clone works on the files directly |
| sutala (server) | Always-on copy | `second-brain-sync.timer` |
| sutala (desktop, niri) | Occasional editing | Open `/srv/appdata/second-brain/vault` in Obsidian **without** the Git plugin; the timer syncs it |
| iPhone | Quick capture, lookups, weekly review | Claude app → **Remote Control** into a Claude Code session on sutala started in `~/second-brain` (needs sutala online, not Tailscale); URL clips via the share-sheet clipper |

Why not a claude.ai custom connector: those calls come from Anthropic's servers, not the phone, so
they need a public endpoint. Remote Control gives the phone the same tools with nothing exposed.

kra3 is in the `second-brain` group (log out and in once after the first deploy) and the vault
carries default ACLs, so files written by kra3 (desktop Obsidian, the MCP server, Claude Code) stay
writable by the sync service.

**Conflicts:** if sutala's commits can't rebase onto the hub (the same lines changed on the Mac and on
sutala between syncs), sutala pushes them to a `conflict/sutala-<time>` branch, resets the vault to the
hub's `main` and the run fails (visible in Loki). Merge the branch on the Mac and delete it.

## Setup

1. **GitHub:** create a private repo `kra3/second-brain`, empty (no README).
2. **Deploy key:** on sutala, in `nix develop`, on this branch: `just second-brain-secrets`. It
   generates `second-brain.git.deploy_key` (on stdin to `sops set`, never argv) and prints the public
   key: add it on the repo under Settings → Deploy keys, **with write access**. Commit the updated
   `secrets/secrets.yaml`.
3. **Config:** check `sync.remote`, set `sync.enable = true` and merge; the nightly upgrade deploys it.
   The server vault starts empty and takes the hub's content on its first sync (it refuses to adopt a
   hub over a non-empty server vault).
4. **Mac:** clone the repo (`git clone git@github.com:kra3/second-brain.git`), copy the contents of
   `docs/second-brain-starter/` (including `.gitignore`) into it, open the folder as a vault in
   Obsidian, install the **Obsidian Git** community plugin and set: auto commit-and-sync interval
   5 min, auto pull on startup, pull before push. In Obsidian, set the Daily notes folder to
   `0 Inbox` and the Templates folder to `Templates`. Its first sync pushes the starter kit;
   sutala picks it up within 5 minutes.
5. **Phone:** on sutala, start `claude` in `~/second-brain` with Remote Control enabled, then open
   that session from the Claude app. Say "save to my inbox: …", "what did I note about …?" or
   "weekly review".

Tools:

| Purpose | Tools |
| --- | --- |
| Read | `list_notes`, `read_note`, `search_notes` |
| Write | `capture` (timestamped note in `0 Inbox`), `write_note` (no overwrite unless asked), `append_to_note`, `move_note` |
| Weekly review | `list_tasks` (open `- [ ]` tasks per note, `waiting:` flagged, archive skipped), `recent_changes`, `orphans` (unlinked notes in `4 Notes`), `backlinks` |

All paths stay inside the vault; dot-folders (`.obsidian`, `.trash`) are refused; writes are atomic.
There's no delete tool: archive with `move_note`. Every change is a git commit either way.

## Checking it works

Logs reach Loki through the host Alloy agent's catch-all journal source:

- Sync healthy: `{host="sutala", systemd_unit="second-brain-sync.service"} |~ "(?i)fatal|error|refusing|conflict"` should be empty.
- On the host: `systemctl list-timers second-brain-sync`,
  `git --git-dir=/srv/appdata/second-brain/vault.git log --oneline -3`, and in `~/second-brain`,
  `claude mcp list` shows `second-brain` connected.

## Later

- **Plain-text capture without Claude:** the share-sheet clipper (`clip.${domain}`, tailnet-only,
  bearer token) takes URLs only; a text mode would let an iOS Shortcut drop a capture into
  `0 Inbox` over Tailscale in seconds.
- **Quartz web view:** a read-only, tailnet-only site of the vault for browsing on the phone.
- **Self-hosted LiveSync** (free Obsidian community plugin, CouchDB on sutala, Tailscale-only), if
  Obsidian on the phone with near-real-time sync becomes worth it. Needs CouchDB (~100–200 MB RAM)
  plus a headless LiveSync client (livesync-bridge on Deno, or the LiveSync CLI on Node) packaged
  for Nix to keep the plain-file vault the MCP server and git use. Git stays as the history.
