# Second brain on sutala

`modules/services/second-brain/default.nix` (`flake.nixosModules.services-second-brain-default`)
keeps a live copy of the Obsidian vault on sutala and gives Claude access to it:

| Part | Unit | What it does |
| --- | --- | --- |
| Sync | `second-brain-sync.service` | Official headless Obsidian Sync client (`ob sync --continuous`, nixpkgs-unstable `obsidian-headless`) into `/srv/appdata/second-brain/vault` |
| Snapshot | `second-brain-snapshot.timer` (hourly) | Commits the vault to `/srv/appdata/second-brain/vault.git` (outside the vault, so Sync never sees it); pushes to `snapshot.remote` when set |
| MCP | `second-brain-mcp.service` | FastMCP server (`mcp_server.py`) on `127.0.0.1:8765`; OAuth via Authelia (`second-brain` client, `admin_only` policy) |
| Funnel | `second-brain-funnel.service` | `tailscale funnel --bg --https=8443` → `https://<publicHost>:8443/mcp` |

Each part is off in `hosts/sutala/configuration.nix` until its secrets exist: sops-nix rejects
a declared key that is missing from `secrets/secrets.yaml`, which would break the nightly upgrade. Turn them on in this order.

Device flow: Linux PC, Mac and iPhone run Obsidian with Obsidian Sync. Only sutala runs
the headless client — never enable the desktop app's Sync on sutala as well; Obsidian
warns that running both on one device causes conflicts.

## 1. Sync

1. On any machine with Nix, log in once to get an auth token (keep the token; don't
   run `ob logout` there, it revokes the token server-side):

   ```sh
   NIXPKGS_ALLOW_UNFREE=1 nix run --impure github:NixOS/nixpkgs/nixpkgs-unstable#obsidian-headless -- login
   cat ~/.config/obsidian-headless/auth_token   # Mac: ~/.obsidian-headless/auth_token
   ```

2. `just sops-edit` and add:

   ```yaml
   second-brain.obsidian.auth_token: <token from step 1>
   second-brain.obsidian.vault_password: <the vault's end-to-end encryption password>
   ```

   (Vault on standard encryption instead? Set `sync.endToEndEncrypted = false` and skip the password.)

3. In `hosts/sutala/configuration.nix` set `services.secondBrain.sync.vaultName` to the remote
   vault's exact name and `sync.enable = true`. On first start the unit runs `ob sync-setup`
   once (state in `/srv/appdata/second-brain/state/config/obsidian-headless`), then follows changes.

## 2. Snapshot

1. `snapshot.enable = true` keeps history on sutala only — enough on its own.
2. To push off-box: create a private GitHub repo, generate a deploy key with write access
   (`ssh-keygen -t ed25519 -N "" -f second-brain-deploy`), add the public half under the
   repo's Settings → Deploy keys, and the private half to sops as
   `second-brain.git.deploy_key`. Then set `snapshot.remote = "git@github.com:kra3/<repo>.git"`.

## 3. MCP server for Claude (web, iPhone app, Claude Code)

1. Tailscale admin console: enable HTTPS certificates (DNS page) and grant Funnel to sutala
   in the tailnet policy, e.g.
   `"nodeAttrs": [{ "target": ["autogroup:member"], "attr": ["funnel"] }]`.
2. Generate the Authelia client secret and its hash:

   ```sh
   nix shell nixpkgs#authelia -c authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986
   ```

   `just sops-edit` and add the **Random Password** as `second-brain.mcp.oidc_client_secret`
   and the **Digest** as `authelia.oidc_clients.second-brain.client_secret_hash`.
3. Set `mcp.publicHost` to sutala's MagicDNS name (`tailscale status --json | jq -r .Self.DNSName`,
   without the trailing dot) and `mcp.enable = true`.
4. claude.ai → Settings → Connectors → Add custom connector →
   `https://<publicHost>:8443/mcp`. Claude registers itself (dynamic client registration) and
   sends you to Authelia. **Sign-in needs the device on Tailscale or the LAN** — Authelia
   (`auth.karunagath.in`) is not public; only the MCP endpoint is. Afterwards the connector
   works from anywhere, including the iPhone app.
5. Claude Code: `claude mcp add --transport http second-brain https://<publicHost>:8443/mcp`.

Tools: `list_notes`, `read_note`, `search_notes`, `capture` (timestamped note in `0 Inbox`),
`write_note` (no overwrite unless asked), `append_to_note`, `move_note`. All paths stay inside
the vault; dot-folders (`.obsidian`, `.trash`) are refused; writes are atomic. No delete tool —
archive with `move_note`; Obsidian Sync keeps version history either way.

## Checking it works

Logs reach Loki through the host Alloy agent's catch-all journal source:

- Sync healthy: `{host="sutala", systemd_unit="second-brain-sync.service"}` — expect steady
  sync lines, no restart loop (`|= "linking"` should appear once, on first start only).
- Snapshot: `{host="sutala", systemd_unit="second-brain-snapshot.service"} |~ "(?i)error|fatal|rejected"` — should be empty.
- MCP: `{host="sutala", systemd_unit="second-brain-mcp.service"} |= "401"` spikes are unauthenticated probes (normal on a public endpoint); `|= "Traceback"` is a real failure.
- On the host: `systemctl status second-brain-sync second-brain-mcp second-brain-funnel`,
  `tailscale funnel status`, `git --git-dir=/srv/appdata/second-brain/vault.git log --oneline -3`.
