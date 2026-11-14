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
| `claudeDir` | `second-brain/<name>` | `second-brain/<name>` | Under `$HOME`: `.mcp.json`, project settings, a `CLAUDE.md` pointer |
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
6. **Phone:** once, as kra3 on sutala, run `cd ~/second-brain/home && claude`: accept the folder
   trust prompt (Remote Control refuses an untrusted folder, and that choice stays yours) and
   `/login` if asked. The
   `second-brain-home-remote` user service then keeps `claude remote-control` running in
   `~/second-brain/home`; in the Claude app, open **second-brain-home** to start a session there.
   Check it with `systemctl --user status second-brain-home-remote`.

## Setup: work brain (work overlay)

1. Create the repo on the work git server, empty.
2. In the overlay: import `homeManagerModules.home-second-brain`, set
   `programs.secondBrain.brains.work.sync = { enable = true; remote = "…"; };` and switch. The agent uses your normal ssh setup over the VPN; logs go to
   `~/Library/Logs/second-brain-work-sync.log`.
3. Copy `docs/second-brain-starter/` into `~/Brains/work`, open it in Obsidian, and run Claude Code in
   `~/second-brain/work`.
4. Work phone (optional): Obsidian + the Obsidian Git plugin, cloning over HTTPS with an access
   token on the VPN, if your device policy allows it; otherwise use the git server's web UI to read
   and to add captures to `0 Inbox/`.

## Checking it works

- sutala: `{host="sutala", systemd_unit=~"second-brain-.*-sync.service"} |~ "(?i)fatal|error|refusing|conflict"`
  should be empty (remote-unreachable lines are fine); `systemctl list-timers 'second-brain-*'`;
  `git --git-dir=/srv/appdata/second-brain/home/vault.git log --oneline -3`.
- Macs: `launchctl list | grep second-brain`, `tail ~/Library/Logs/second-brain-<name>-sync.log`.
- Claude: in `~/second-brain/<name>`, `claude mcp list` shows `second-brain` connected.

## Clipper: share a reel or video, get a capture

`modules/services/second-brain/clipper.nix` (`services-second-brain-clipper`) + `clipper.py`.
Share an Instagram reel, a YouTube video or Short (anything yt-dlp handles) from the iPhone share
sheet. A capture lands in the brain's `0 Inbox` (default brain: `home`), and the brain's git sync
carries it to the hub and every device within one sync interval or so.

```
Share sheet → "Clip to Second Brain" Shortcut ──POST /clip──▶ https://clip.<domain>  (LAN/tailnet only)
  second-brain-clipper.service (user second-brain, Nice 10, CPUWeight 20, MemoryMax 4G)
    1. yt-dlp metadata: title, author, caption/description, upload date
    2. transcript: platform subtitles when present (most YouTube), else
       audio → faster-whisper (`clipper.whisperModel`, default small, CPU int8)
    3. Claude (`clipper.summaryModel`, default claude-haiku-5-5): title, summary, key points,
       0–3 candidate evergreen ideas (claims only; Arun writes the notes)
    4. atomic write → <vault>/0 Inbox/YYYY-MM-DD HHMM <title>.md → next second-brain-<brain>-sync run
```

The note follows the [vault rules](second-brain-starter/CLAUDE.md): frontmatter `created`,
`type: capture`, `source` (the link), `kind: video`, plus `platform`, `author`, `published`,
`duration` and `transcript` (`subtitles` or `whisper-<model> (<lang>)`); no topic tags, and the
caption's hashtags are escaped so Obsidian doesn't turn them into tags. Body: Claude's draft
summary (marked as a draft to rewrite when filing), key points, `- [ ]` ideas for evergreen notes,
the original caption, the full transcript. In the weekly review it clarifies like any capture,
usually into a source stub in `3 Sources`.

The request returns `202 queued` at once. Jobs live in `/srv/appdata/second-brain/clipper/queue`
and survive restarts; each is tried three times (1 and 2 minutes apart), then a `Clip failed`
capture (`clip: failed`) with the error lands in the inbox instead, so a share never vanishes.
The same link shared again answers `exists` with the note's path; `{"url": "…", "force": true}`
redoes it.

### Setup

1. **Secrets:** on sutala, in `nix develop`: `just clipper-secrets`. It generates
   `second-brain.clipper.token` and asks for a Claude Code subscription token
   (`second-brain.clipper.claude_oauth_token`): run `claude setup-token` on a machine logged in to
   your Claude subscription and paste what it prints. Summaries run through the `claude` CLI
   (all tools disabled), so they use the subscription's usage, with no API billing. Commit
   `secrets/secrets.yaml`.
2. **Config:** `services.secondBrain.clipper.enable = true;` in `hosts/sutala/configuration.nix`
   (`clipper.brain` picks the brain; it must have `sync.enable`). Merge; the nightly upgrade
   deploys it. The first clip that needs Whisper downloads the model (~500 MB for `small`) into
   `/srv/appdata/second-brain/clipper/models`.
3. **Instagram, only if anonymous fetching fails:** export a Netscape `cookies.txt` from a
   logged-in browser, `sops set` it as `second-brain.clipper.cookies`, and set
   `clipper.instagramCookies = true`. Use a throwaway account: Instagram may flag scraping.
4. **iPhone Shortcut** (Shortcuts → + → *Clip to Second Brain*):
   - Details (ⓘ): **Show in Share Sheet** on; accepted types **URLs** and **Text** (Instagram
     shares text with the link inside; the server takes the first link).
   - **Get Contents of URL**: `https://clip.<domain>/clip`, Method **POST**, Header
     `Authorization` = `Bearer <token>`, Request Body **JSON**: key `url` (Text) = *Shortcut Input*.
   - **Get Dictionary Value** `status` from *Contents of URL* → **Show Notification**
     "Clip: *Dictionary Value*".

   The phone must be on home Wi-Fi or Tailscale (`nginxAllowCidrs`: LAN + `100.64.0.0/10`).

### Checking it works

- After a share: `{host="sutala", systemd_unit="second-brain-clipper.service"} |= "clipped"` shows
  `clipped <url> -> 0 Inbox/<note>.md (<transcript source>)`, and the next
  `second-brain-<brain>-sync` run pushes it.
- Failures: `{host="sutala", systemd_unit="second-brain-clipper.service"} |~ "ERROR|Traceback"`;
  inbox captures with `clip: failed`.
- On the host: `curl -s https://clip.<domain>/health` → `{"ok": true, "queued": N}`.

## Later

- **Plain-text capture without Claude:** the [clipper](#clipper-share-a-reel-or-video-get-a-capture)
  takes video links only; a text mode would let an iOS Shortcut drop any capture into the
  home brain's `0 Inbox` over Tailscale.
- **Quartz web view:** a read-only, tailnet-only site of a vault for browsing on the phone.
- **Self-hosted LiveSync** (free Obsidian plugin, CouchDB on sutala, Tailscale-only), if Obsidian
  on the phone with near-real-time sync becomes worth it. ~200–350 MB RAM plus a headless LiveSync
  client packaged for Nix; git stays as the history.
