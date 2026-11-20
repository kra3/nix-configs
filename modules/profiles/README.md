# Profiles

Purpose-based bundles of NixOS modules, registered as `flake.nixosModules.profiles-<path>` (path under `modules/profiles/`, `/` to `-`, same flat naming rule as everything else). A host imports profiles instead of listing individual modules. Container stacks under `modules/containers/` are not moved; profiles import them and carry the small config that belongs to the profile (its postgres db, its firewall forward rules, its NAT port forwards).

## Role vocabulary

| Role | Meaning |
|---|---|
| `server` | Runs the service itself |
| `acquire` | Fetches or manages content for a server (arr-stack, slskd, ...) |
| `player` | Plays media on this host |
| `agent` | Per-host collector that reports to a server (Alloy) |
| `primary` / `secondary` | Redundant pair (DNS) |
| `shared` | Network/storage common to a stack; imported by that stack's other profiles |
| `voice`, `notify`, `extras`, `watchdog`, `hub`, `budget`, `investments` | Named after the capability they add |

## Profiles

| Profile | Modules | Hosts |
|---|---|---|
| `base-server` | vars, nix-defaults-nixos, openssh, sops, acme, fail2ban, `observability-agent` | sutala, surasa |
| `observability-agent` | alloy-host | via `base-server` |
| `observability-server` | containers-monitoring, postgres; rules 1-5 | sutala |
| `observability-watchdog` | sutala-watchdog | surasa |
| `dns-primary` | dns-default | sutala |
| `dns-secondary` | dns-rpi-secondary | surasa |
| `edge` | nginx, authelia (+ `users-authelia`), homepage, tailscale | sutala |
| `home-automation-server` | containers-home-auto (+ home-assistant, otbr, matter-server), postgres (hass db); rules 6, 6a, 7, 10, 11; MQTT/WebRTC `nat.forwardPorts` | sutala |
| `home-automation-voice` | wyoming-whisper, wyoming-piper | sutala |
| `surveillance-server` | surveillance-proxy | sutala |
| `surveillance-notify` | camera-announce (asserts Piper from `home-automation-voice`) | sutala |
| `second-brain-hub` | second-brain, second-brain-clipper | sutala |
| `fitness-server` | fitness | sutala |
| `life-shared` | containers-life-network, -storage; rule 11 | via the three below |
| `finance-budget` | life-shared, actualbudget | sutala |
| `finance-investments` | life-shared, ghostfolio, postgres (ghostfolio db), redis | sutala |
| `passwords-server` | life-shared, vaultwarden | sutala |
| `media-shared` | media-mgmt network, storage, prowlarr, sabnzbd; rule 11 | via the media profiles |
| `media-video-server` | media-shared, media-play (enables Jellyfin), iptv; rules 8, 9 | sutala |
| `media-video-acquire` | media-shared, radarr, sonarr, recyclarr, maintainerr, seerr; rule 9a | sutala |
| `media-video-extras` | media-shared, bazarr, unpackerr | none (importing it turns them on) |
| `media-video-player` | lg-devmode-extend | sutala |
| `media-music-server` | music-assistant (Navidrome lives inside media-play) | sutala |
| `media-music-acquire` | media-shared, lidarr, slskd, beets webhook, failed-import recovery | sutala |
| `media-music-player` | sendspin | sutala |
| `media-music-player-headless` | music-player, pi-audio | surasa |
| `media-reading-server` | media-shared, audiobookshelf | sutala |
| `media-reading-acquire` | media-shared, bookshelf, rreading-glasses, postgres (rreading_glasses db) | sutala |
| `media-streaming-server` | media-shared, aiostreams, aiometadata, redis | sutala |

mac-work (nix-darwin) uses no NixOS profiles; it uses `home-profiles-*` (see `modules/home/profiles/`).
Host-specific values (player names, sinks, IPs, the office-amp bluetooth loop, second-brain settings) stay in the host file.

## Rules

- **Dedup `key`.** flake-parts registry modules are not de-duplicated when two profiles import the same one: list options merge twice and unique options conflict. A module imported by more than one profile must return `key = "<its registered name>";` (see `media/shared.nix`, `life/shared.nix`). Modules imported by a single profile need none.
- **Presence checks, not flags.** There is no `vars.localMedia`. Importing a profile is the switch, and consumers test for the thing they need: `config.virtualisation.quadlet.containers ? radarr` for quadlet apps, the Jellyfin enable option for Jellyfin (video/server turns it on). Homepage tiles, Prometheus scrape targets, storage and firewall rules follow this.
- **`or false` for container-internal reads.** `config.containers.media-play.config...` does not exist on a host without `media-play`, so read it as `config.containers.media-play.config.services.declarative-jellyfin.enable or false`, uniformly, in every consumer. Quadlet presence (`? name`) needs no `or`.
- **Rules between profiles.** A profile that depends on another says so in a one-line comment, or asserts it when the failure would otherwise be silent (`surveillance-notify` asserts Piper). Firewall forward rules live in the profile of the destination service (monitoring scrapes and Loki shipping in `observability-server`); `ct state established,related accept` stays in the host (belt-and-braces, see below).

## Known limitations

- **Postgres password script coupling.** `postgresql-set-passwords` in `modules/services/postgres.nix` hard-codes the ghostfolio, hass, rreading_glasses and grafana_ro roles (and their sops secrets). A host importing `services-postgres` must therefore also import `finance-investments`, `home-automation-server` and `media-reading-acquire` (true on sutala). Each profile owns its db and user but not yet the password step; making that per-profile is a follow-up.
- **Grafana to hass coupling.** The Grafana "Home Assistant" datasource in `observability-server` reads the hass db as `grafana_ro`, so `home-automation-server` must be present with it.
- **media-play is shared by two profiles.** `media-music-server` relies on `media-video-server` for media-play (Navidrome is inside it); `media-video-extras` expects radarr/sonarr from `media-video-acquire`.
- **Cross-profile forward rules in observability-server.** It carries scrape and log-shipping rules for destinations owned by other profiles (navidrome 4533, slskd 5030, home-auto 9100/80/8123). Fine with one server host; if the profiles are ever split across hosts these rules should become conditional or move to the destination profiles.
- **established/related is not order-critical.** nixpkgs accepts established/related in the forward chain before `forward-allow`, so the host's own `ct state established,related accept` line is belt-and-braces, not required to be first.
