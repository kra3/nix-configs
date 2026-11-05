# Second brain on sutala

`modules/services/second-brain/default.nix` (`flake.nixosModules.services-second-brain-default`)
keeps a copy of the Obsidian vault on sutala, in sync with the Mac through a private GitHub
repo, and gives Claude access to it. Everything is free: no Obsidian Sync subscription.

| Part | Unit | What it does |
| --- | --- | --- |
| Sync | `second-brain-sync.timer` (every 5 min) | `sync.sh`: commits sutala's changes, rebases onto the hub's `main`, pushes. Work tree `/srv/appdata/second-brain/vault`, git dir `/srv/appdata/second-brain/vault.git` (outside the vault) |
| MCP | `second-brain-mcp.service` | FastMCP server (`mcp_server.py`) on `127.0.0.1:8765`; OAuth via Authelia (`second-brain` client, `admin_only` policy) |
| Funnel | `second-brain-funnel.service` | `tailscale funnel --bg --https=8443` → `https://<publicHost>:8443/mcp` |

Each part is off in `hosts/sutala/configuration.nix` until its secrets exist: sops-nix rejects
a declared key that is missing from `secrets/secrets.yaml`, which would break the nightly upgrade.

## Devices

| Device | Role | How it syncs |
| --- | --- | --- |
| Mac | Main writing | Obsidian + the Obsidian Git community plugin, auto pull/commit/push every few minutes |
| sutala (server) | Always-on copy for Claude | `second-brain-sync.timer` |
| sutala (desktop, niri) | Occasional editing | Open `/srv/appdata/second-brain/vault` in Obsidian **without** the Git plugin; the timer syncs it |
| iPhone | Quick capture and lookups | No vault on the phone: the Claude app's `second-brain` connector (`capture`, `search_notes`, ...) |

kra3 is in the `second-brain` group (log out and in once after the first deploy) and the vault
carries default ACLs, so files you create there from desktop Obsidian stay writable by the sync service.

**Conflicts:** if sutala's commits can't rebase onto the hub (the same lines changed on the Mac and on
sutala between syncs), sutala pushes them to a `conflict/sutala-<time>` branch, resets the vault to the
hub's `main` and the run fails (visible in Loki). Merge the branch on the Mac and delete it.

## Setup

1. **GitHub:** create a private repo `kra3/second-brain`, empty (no README).
2. **Tailscale admin console:** enable HTTPS certificates (DNS page) and grant Funnel to sutala
   in the tailnet policy, e.g. `"nodeAttrs": [{ "target": ["autogroup:member"], "attr": ["funnel"] }]`.
3. **Secrets:** on sutala, in `nix develop`, on this branch: `just second-brain-secrets`. It is
   idempotent and only adds keys that are missing:
   - generates `second-brain.git.deploy_key` and prints the public key: add it on the repo under
     Settings → Deploy keys, **with write access**;
   - generates the Authelia client secret and its PBKDF2 digest →
     `second-brain.mcp.oidc_client_secret` + `authelia.oidc_clients.second-brain.client_secret_hash`;
   - prints sutala's MagicDNS name.

   Values reach sops on stdin (`sops set --value-stdin`), never on a command line. Commit the
   updated `secrets/secrets.yaml`.
4. **Config:** set `mcp.publicHost` to the printed name, check `sync.remote`, turn on both
   `enable`s and merge; the nightly upgrade deploys it. The server vault starts empty and takes
   the hub's content on its first sync (it refuses to adopt a hub over a non-empty server vault).
5. **Mac:** clone the repo (`git clone git@github.com:kra3/second-brain.git`), unzip the starter kit
   into it, open the folder as a vault in Obsidian, install the **Obsidian Git** community plugin and
   set: auto commit-and-sync interval 5 min, auto pull on startup, pull before push. Its first sync
   pushes the starter kit; sutala picks it up within 5 minutes.
6. **Claude connector:** claude.ai → Settings → Connectors → Add custom connector →
   `https://<publicHost>:8443/mcp`. Claude registers itself (dynamic client registration), shows
   FastMCP's consent page, then sends you to Authelia. **Sign-in needs the device on Tailscale or the
   LAN**: Authelia (`auth.karunagath.in`) is not public; only the MCP endpoint is. Afterwards the
   connector works from anywhere, including the iPhone app.
7. **Claude Code elsewhere (optional):** `claude mcp add --transport http second-brain https://<publicHost>:8443/mcp`.
8. **Close registration:** once the connectors you want are connected, set
   `mcp.allowNewClients = false` and deploy. The endpoint is public and anyone can register a
   client named "Claude" with claude.ai's redirect, so while it's open, only click **Allow** on
   the consent page right after you started a connection yourself. Closed, `/register` and URL
   (CIMD) client ids are refused; already-connected clients keep working. Reopen it to add one.

Tools: `list_notes`, `read_note`, `search_notes`, `capture` (timestamped note in `0 Inbox`),
`write_note` (no overwrite unless asked), `append_to_note`, `move_note`. All paths stay inside
the vault; dot-folders (`.obsidian`, `.trash`) are refused; writes are atomic. No delete tool:
archive with `move_note`. Every change is a git commit either way.

## Checking it works

Logs reach Loki through the host Alloy agent's catch-all journal source:

- Sync healthy: `{host="sutala", systemd_unit="second-brain-sync.service"} |~ "(?i)fatal|error|refusing|conflict"` should be empty.
- MCP: `{host="sutala", systemd_unit="second-brain-mcp.service"} |= "401"` spikes are unauthenticated probes (normal on a public endpoint); `|= "Traceback"` is a real failure.
- On the host: `systemctl list-timers second-brain-sync`, `systemctl status second-brain-mcp second-brain-funnel`,
  `tailscale funnel status`, `git --git-dir=/srv/appdata/second-brain/vault.git log --oneline -3`.

## Later

- **Self-hosted LiveSync** (free Obsidian community plugin, CouchDB on sutala, Tailscale-only), if
  Obsidian on the phone with near-real-time sync becomes worth it. Needs CouchDB (~100–200 MB RAM)
  plus a headless LiveSync client (livesync-bridge on Deno, or the LiveSync CLI on Node) packaged
  for Nix to keep the plain-file vault the MCP server and git use. Git stays as the history.
