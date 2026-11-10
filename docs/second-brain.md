# Second brains

A second brain is one Obsidian vault plus its own git hub repo. Each machine declares which brains
it holds; nothing listens on the network, and brains never share a repo, folder or Claude session.

| Piece | File | Used by |
| --- | --- | --- |
| Sync script (`sync.sh`), MCP server (`mcp_server.py`), builders | `modules/lib/second-brain/` (`flake.lib.second-brain-packages`) | both modules |
| NixOS module: always-on server copies, system timer, deploy key from sops | `modules/services/second-brain/default.nix` (`services-second-brain-default`) | sutala |
| Home Manager module: the user's own vaults, launchd agent (macOS) / systemd user timer (Linux), the user's ssh setup | `modules/home/second-brain.nix` (`home-second-brain`) | Macs that import it (e.g. the work overlay) |
| Vault template: folders, `CLAUDE.md` rules, templates | `docs/second-brain-starter/` | every new vault |

## Brains and machines

| Brain | Hub | sutala | Work Mac | Personal Mac (later) | Personal iPhone | Work phone |
| --- | --- | --- | --- | --- | --- | --- |
| home | `github.com/kra3/second-brain` (private) | Server copy + MCP (personal Claude) | Opt-in, files only (no Claude) | Vault + MCP | Remote Control → sutala; optionally Obsidian + Git plugin | Never |
| work | Work git server (over the VPN) | Never | Vault + MCP (work Claude Code) | Never | Never | Obsidian + Git plugin over VPN if allowed, else the git web UI |

No host in this repo sets up a work brain. The mac-work host here is a baseline, and the private
work overlay on top of it imports the exported module and declares the brain, so nothing about the
work brain lands here. The module takes its builders from this flake, not from a `flakeLib`
specialArg, so another flake can import it as-is:

```nix
home-manager.users.<me>.imports = [ inputs.nix-configs.homeManagerModules.home-second-brain ];
```

## Options

`services.secondBrain.brains.<name>` (NixOS, sutala) and `programs.secondBrain.brains.<name>`
(Home Manager, Macs) take the same shape:

| Option | NixOS default | Home Manager default | Notes |
| --- | --- | --- | --- |
| `enable` | `true` | `true` | Declaring a brain enables it |
| `vaultDir` | `/srv/appdata/second-brain/<name>/vault` | `~/Brains/<name>` | The folder Obsidian opens; a git work tree |
| `gitDir` | `…/<name>/vault.git` | `<vaultDir>.git` | Kept outside the vault |
| `claudeDir` | `agents/second-brain-<name>` | `agents/second-brain-<name>` | The brain's agent folder under `$HOME` (all agents live in `~/agents`): `.mcp.json`, project settings, a `CLAUDE.md` pointer. One folder per brain keeps a session from seeing two brains; sutala only holds one, so it uses `agents/second-brain` |
| `mcp.enable` | `true` | `true` | Local stdio MCP server in `claudeDir`; set `false` for a files-only brain |
| `sync.enable` | `false` | `false` | Two-way git sync every interval |
| `sync.remote` | (required with sync) | (required with sync) | Hub repo URL |
| `sync.interval` / `sync.intervalSeconds` | `"5min"` | `300` | |
| `remoteControl.enable` | `false` | n/a | Always-on `claude remote-control` in `claudeDir` (kra3 user service, lingering) so the phone can always connect |
| `remoteControl.permissionMode` | `"default"` | n/a | `acceptEdits` skips approving each edit from the phone |
| `sync.deployKeySecret` | `second-brain.<name>.git.deploy_key` | n/a | Home Manager uses the user's own ssh keys, config and agent |
| `programs.secondBrain.hostLabel` | n/a | `"mac"` | Names the machine in commits and `conflict/<host>-…` branches; sutala uses its hostname |

Examples:

```nix
# sutala (hosts/sutala/configuration.nix)
services.secondBrain.brains.home.sync = { enable = true; remote = "git@github.com:kra3/second-brain.git"; };

# work overlay on top of mac-work (after importing the module, above)
programs.secondBrain.hostLabel = "work-mac";
programs.secondBrain.brains.work.sync = { enable = true; remote = "git@git.corp.example:me/brain.git"; };
# opt-in, files only:
programs.secondBrain.brains.home = { mcp.enable = false; sync = { enable = true; remote = "git@github.com:kra3/second-brain.git"; }; };

# personal Mac, once it's a host here
programs.secondBrain.hostLabel = "mac";
programs.secondBrain.brains.home.sync = { enable = true; remote = "git@github.com:kra3/second-brain.git"; };
```

## Sync

Every device holding a brain runs `sync.sh` every interval: commit local changes → fetch → rebase
onto the hub's `main` → push. Other devices see a change within about 5–10 minutes.

- **Hub unreachable** (offline, VPN down): changes are committed locally, the run exits 75 (not a
  failure), and the next run catches up.
- **Conflict** (same lines changed on two devices between syncs): this device's commits go to
  `conflict/<host>-<time>` on the hub, the vault resets to `main`, and the run fails visibly. Merge
  the branch on a machine with the vault.
- **First sync** adopts the hub's history only into an empty vault; it refuses otherwise.
- Phones with the Obsidian Git plugin take part like any other clone (HTTPS + access token; the
  plugin's settings file is git-ignored so the token is never committed).

## Method

Two layers, with Claude doing the filing:
- **action:** PARA folders plus GTD capture, clarify and weekly review;
- **knowledge:** Zettelkasten/evergreen notes plus maps of content.

```
0 Inbox → (weekly clarify) → 1 Projects / 2 Areas  (tasks)
                           → 3 Sources → 4 Notes (evergreen, your words) → 5 Maps
projects draw on notes and maps (express); finished things → 6 Archive
```

`docs/second-brain-starter/CLAUDE.md` holds the folder rules, the weekly review and the rule that
Claude suggests but never writes evergreen notes.

## Claude access

- Claude Code in `~/<claudeDir>` gets that brain's tools; a session sees only one brain.
- Personal iPhone: Claude app → **Remote Control** into the session on sutala (personal account).
- Work: Claude Code on the work Mac only (no Claude app, so no Remote Control from the work phone).
- If a managed Claude Code policy blocks project MCP servers, Claude still works on the vault's files.

Tools:

| Purpose | Tools |
| --- | --- |
| Read | `list_notes`, `read_note`, `search_notes` |
| Write | `capture` (timestamped note in `0 Inbox`), `write_note` (no overwrite unless asked), `append_to_note`, `move_note` |
| Weekly review | `list_tasks` (open `- [ ]` tasks per note, `waiting:` flagged, archive skipped), `recent_changes`, `orphans` (unlinked notes in `4 Notes`), `backlinks` |

All paths stay inside the vault; dot-folders are refused; writes are atomic; there is no delete tool.

## Setup: home brain

1. **GitHub:** create a private repo `kra3/second-brain`, empty (no README).
2. **Deploy key (sutala):** in `nix develop`, `just second-brain-secrets home`. It adds
   `second-brain.home.git.deploy_key` to sops via stdin and prints the public key: add it on the repo
   under Settings → Deploy keys **with write access**, then commit `secrets/secrets.yaml`.
3. **Enable:** set `services.secondBrain.brains.home.sync.enable = true` and merge; the nightly
   upgrade deploys it. The empty server vault takes the hub's content on its first sync.
4. **First content:** copy `docs/second-brain-starter/` (including `.gitignore`) into the server
   vault, or into a Mac's vault once one holds the home brain; the next sync pushes it.
5. **Obsidian** (installed on sutala via `hosts/sutala/home.nix`): open the vault; set the Daily notes folder to `0 Inbox` and Templates to
   `Templates`. On sutala's desktop open `/srv/appdata/second-brain/home/vault` (kra3 is in the
   `second-brain` group; log out and in once after the first deploy). No sync plugin on machines
   that run the agent or timer.
6. **Phone:** once, as kra3 on sutala, run `cd ~/agents/second-brain && claude`: accept the folder
   trust prompt (Remote Control refuses an untrusted folder, and that choice stays yours) and
   `/login` if asked. The
   `second-brain-home-remote` user service then keeps `claude remote-control` running in
   `~/agents/second-brain`; in the Claude app, open **second-brain-home** to start a session there.
   Check it with `systemctl --user status second-brain-home-remote`.

## Setup: work brain (work overlay)

1. Create the repo on the work git server, empty.
2. In the overlay: import `homeManagerModules.home-second-brain`, set
   `programs.secondBrain.brains.work.sync = { enable = true; remote = "…"; };` and switch. The agent uses your normal ssh setup over the VPN; logs go to
   `~/Library/Logs/second-brain-work-sync.log`.
3. Copy `docs/second-brain-starter/` into `~/Brains/work`, open it in Obsidian, and run Claude Code in
   `~/agents/second-brain-work`.
4. Work phone (optional): Obsidian + the Obsidian Git plugin, cloning over HTTPS with an access
   token on the VPN, if your device policy allows it; otherwise use the git server's web UI to read
   and to add captures to `0 Inbox/`.

## Checking it works

- sutala: `{host="sutala", systemd_unit=~"second-brain-.*-sync.service"} |~ "(?i)fatal|error|refusing|conflict"`
  should be empty (remote-unreachable lines are fine); `systemctl list-timers 'second-brain-*'`;
  `git --git-dir=/srv/appdata/second-brain/home/vault.git log --oneline -3`.
- Macs: `launchctl list | grep second-brain`, `tail ~/Library/Logs/second-brain-<name>-sync.log`.
- Claude: in `~/agents/second-brain-<name>`, `claude mcp list` shows `second-brain` connected.

## Later

- **Plain-text capture without Claude:** the share-sheet clipper (`clip.${domain}`, tailnet-only,
  bearer token) takes URLs only; a text mode would let an iOS Shortcut drop a capture into the
  home brain's `0 Inbox` over Tailscale.
- **Quartz web view:** a read-only, tailnet-only site of a vault for browsing on the phone.
- **Self-hosted LiveSync** (free Obsidian plugin, CouchDB on sutala, Tailscale-only), if Obsidian
  on the phone with near-real-time sync becomes worth it. ~200–350 MB RAM plus a headless LiveSync
  client packaged for Nix; git stays as the history.
