# Security decisions and accepted risks

Output of the 2026-11 audit. Each entry is either a deliberate exception or a known gap with its reason.

## Accepted

| Area | Decision | Why |
|---|---|---|
| Tailnet reach | `100.64.0.0/10` stays in `nginxAllowCidrs` | Only the owner's devices join the tailnet (unverified; checked 2026-11-21 via `tailscale status`: sutala, surasa, 3 iOS devices) |
| surasa deploy | Daily autodeploy of `main`, passwordless sudo for kra3 | Compensating control is `main` branch protection and PAT scope (unverified, check in GitHub) |
| surasa SSH | Port 22 open on all interfaces | First-boot bootstrap runs over USB ethernet before wifi is configured |
| sshd ciphers | NixOS defaults kept | Already modern; restricting risks locking out the iPad client |
| auditd / AppArmor | Not enabled | Noisy on a podman/nspawn host and not testable off-host |
| Unprivileged userns | Left on | Container compatibility |
| `ma-snapcast` 1705 | Same allow-list as other vhosts | No worse than the other vhosts; Snapcast JSON-RPC has no auth of its own |
| `/api` auth bypasses | arr apps, seerr, fitness `/api/ingest` | Each is guarded by the app's own API key |
| go2rtc `0.0.0.0:1984` | Unchanged | Firewall opens 1984 only on `ve-home-auto`; Home Assistant needs it |
| Alloy group access | None: Alloy has no extra groups and reads journals only | Jellyfin and Grafana log to the journal, so the file sources and their group access were removed |
| LinuxServer images | Start as root, app drops to `abc` | Images do not support `user=` |

## Deferred

- nspawn `privateUsers`: monitoring, media-play and home-auto bind-mount host data and devices; UID shifting needs idmapped mounts and live testing.
- Non-root `user=` for vaultwarden, actualbudget, audiobookshelf, aiometadata: stateful, existing files are root-owned; each needs a recursive ownership fix and a live restart test.
- Authelia email notifier: users' addresses are `@karunagath.in` placeholders; switching needs real addresses and a check that OIDC apps do not match users by email.
- Cloudflare ACME token scope, GitHub PAT scopes and Tailscale ACLs live outside the repo and need a manual check.
