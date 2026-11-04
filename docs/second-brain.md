# Second brain on sutala

`modules/services/second-brain/default.nix` (`flake.nixosModules.services-second-brain-default`)
keeps a live copy of the Obsidian vault on sutala and gives Claude access to it:

| Part | Unit | What it does |
| --- | --- | --- |
| Sync | `second-brain-sync.service` | Official headless Obsidian Sync client (`ob sync --continuous`; flake package `obsidian-headless`, from nixpkgs-unstable) into `/srv/appdata/second-brain/vault` |
| Snapshot | `second-brain-snapshot.timer` (hourly) | Commits the vault to `/srv/appdata/second-brain/vault.git` (outside the vault, so Sync never sees it); pushes to `snapshot.remote` when set |
| MCP | `second-brain-mcp.service` | FastMCP server (`mcp_server.py`) on `127.0.0.1:8765`; OAuth via Authelia (`second-brain` client, `admin_only` policy) |
| Funnel | `second-brain-funnel.service` | `tailscale funnel --bg --https=8443` → `https://<publicHost>:8443/mcp` |

Each part is off in `hosts/sutala/configuration.nix` until its secrets exist: sops-nix rejects
a declared key that is missing from `secrets/secrets.yaml`, which would break the nightly upgrade.

## Devices

| Device | Obsidian Sync | Vault |
| --- | --- | --- |
| Mac, iPhone | Desktop/mobile app's own Sync | Their own copy |
| sutala (server) | `second-brain-sync.service` (headless) | `/srv/appdata/second-brain/vault` |
| sutala (desktop, niri) | **Off** — open the server's copy | Same folder as above |

Never connect the desktop app's Sync on sutala: Obsidian warns that running it alongside the
headless client on one device causes conflicts. Open `/srv/appdata/second-brain/vault` as the
vault instead; the headless client already syncs it. kra3 is in the `second-brain` group (log out
and in once after the first deploy) and the vault carries default ACLs, so files you create there
stay writable by the sync client. Claude Code on sutala can work in that folder directly too.

## Setup

1. **Tailscale admin console:** enable HTTPS certificates (DNS page) and grant Funnel to sutala
   in the tailnet policy, e.g. `"nodeAttrs": [{ "target": ["autogroup:member"], "attr": ["funnel"] }]`.
2. **Optional, off-box history:** create a private GitHub repo for the vault.
3. **Secrets:** on sutala, in `nix develop`, on this branch:

   ```sh
   just second-brain-secrets              # add deploy_key=yes if you did step 2
   ```

   It is idempotent and only adds keys that are missing:
   - `ob login` (email, password, MFA) in a throwaway config dir → `second-brain.obsidian.auth_token`,
     then lists your remote vaults. The throwaway login is never logged out: that would revoke the token.
   - Prompts for the vault's end-to-end encryption password → `second-brain.obsidian.vault_password`
     (empty answer = standard encryption: set `sync.endToEndEncrypted = false`).
   - Generates the Authelia client secret and its PBKDF2 digest →
     `second-brain.mcp.oidc_client_secret` + `authelia.oidc_clients.second-brain.client_secret_hash`.
   - `deploy_key=yes`: generates `second-brain.git.deploy_key` and prints the public key; add it on
     the repo under Settings → Deploy keys with write access.
   - Prints sutala's MagicDNS name.

   Values reach sops on stdin (`sops set --value-stdin`), never on a command line. Commit the
   updated `secrets/secrets.yaml`.
4. **Config:** in `hosts/sutala/configuration.nix` set `sync.vaultName` (from the list above),
   `mcp.publicHost` (the MagicDNS name), `snapshot.remote` if you made a repo, and the three
   `enable`s. Merge; the nightly upgrade deploys it. On first start the sync unit runs
   `ob sync-setup` once (state in `/srv/appdata/second-brain/state/config/obsidian-headless`).
5. **Claude connector:** claude.ai → Settings → Connectors → Add custom connector →
   `https://<publicHost>:8443/mcp`. Claude registers itself (dynamic client registration) and
   sends you to Authelia. **Sign-in needs the device on Tailscale or the LAN**: Authelia
   (`auth.karunagath.in`) is not public; only the MCP endpoint is. Afterwards the connector
   works from anywhere, including the iPhone app.
6. **Claude Code elsewhere (optional):** `claude mcp add --transport http second-brain https://<publicHost>:8443/mcp`.
7. **Close registration:** once the connectors you want are connected, set
   `mcp.allowNewClients = false` and deploy. The endpoint is public and anyone can register a
   client named "Claude" with claude.ai's redirect, so while it's open, only click **Allow** on
   the consent page right after you started a connection yourself. Closed, `/register` and URL
   (CIMD) client ids are refused; already-connected clients keep working. Reopen it to add one.

Tools: `list_notes`, `read_note`, `search_notes`, `capture` (timestamped note in `0 Inbox`),
`write_note` (no overwrite unless asked), `append_to_note`, `move_note`. All paths stay inside
the vault; dot-folders (`.obsidian`, `.trash`) are refused; writes are atomic. No delete tool:
archive with `move_note`. Obsidian Sync keeps version history either way.

## Checking it works

Logs reach Loki through the host Alloy agent's catch-all journal source:

- Sync healthy: `{host="sutala", systemd_unit="second-brain-sync.service"}`: expect steady
  sync lines, no restart loop (`|= "linking"` should appear once, on first start only).
- Snapshot: `{host="sutala", systemd_unit="second-brain-snapshot.service"} |~ "(?i)error|fatal|rejected"` should be empty.
- MCP: `{host="sutala", systemd_unit="second-brain-mcp.service"} |= "401"` spikes are unauthenticated probes (normal on a public endpoint); `|= "Traceback"` is a real failure.
- On the host: `systemctl status second-brain-sync second-brain-mcp second-brain-funnel`,
  `tailscale funnel status`, `git --git-dir=/srv/appdata/second-brain/vault.git log --oneline -3`.
