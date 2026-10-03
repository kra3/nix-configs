# Host & Service Inventory

Generated from the state of `modules/` and `hosts/` on `main`. For full
network topology, ports, and firewall rules, see
[`network-diagram.md`](./network-diagram.md) — this document focuses on
*which nix file defines what*, per host, plus the logging/metrics pipeline.

## Hosts at a glance

| Host | Role | Arch | Deploy |
|---|---|---|---|
| `sutala` | Home server + desktop (niri) | x86_64-linux | `just switch sutala` (local) |
| `surasa` | Secondary DNS resolver + Snapcast client + off-box watchdog | aarch64-linux (RPi 3B+) | `just switch-remote surasa <target>`, built on sutala |
| `mac-work` | Work laptop (nix-darwin, Home Manager only) | aarch64-darwin | `just switch mac-work` (local, Determinate-managed nix) |

---

## `sutala`

### Role
Primary home server: media library + streaming, home automation/NVR, DNS,
SSO, monitoring, and the desktop (niri) session when used interactively.
Config: `hosts/sutala/configuration.nix`.

### Hardware
- Dell 0HMF7C, Comet Lake Intel CPU + iGPU (`modules/hardware/intel-igpu.nix`,
  QSV/VAAPI/OpenCL via `i915`).
- Storage: NVMe (Kingston 2TB, `rpool` — root/nix/appdata/databases) + SATA
  HDD (Hitachi 3TB, `tank` — media/surveillance), ZFS on both, defined in
  `hosts/sutala/disko.nix`. Autoscrub, autosnapshot, and weekly trim enabled
  in `hosts/sutala/configuration.nix`.
- Single LAN NIC `enp2s0` (`192.168.1.10/24`); `binfmt.emulatedSystems` set
  so this host can also cross-build surasa's aarch64-linux closure.

### Network config
LAN `192.168.1.0/24` on `enp2s0`; default-deny `nftables` FORWARD with an
explicit inter-zone allow-list; Tailscale exit node + subnet route for
`192.168.1.10/32`. Three isolation mechanisms in play — nspawn containers
(`monitoring`, `media-play`, `home-auto`, each its own veth on
`10.3.255.0/24`), podman quadlet zones (`br-life` 10.3.0.0/24,
`br-media-mgmt` 10.3.1.0/24, `br-home-auto` 10.3.2.0/24, plus a macvlan for
LAN-discoverable home-auto pods), and two standalone rootless podman
instances (arcane, authelia). Full diagram, port list, and the FORWARD
allow-table: [`network-diagram.md`](./network-diagram.md).

### Services

#### Host-level infrastructure

| Service | Defining file(s) | Notes |
|---|---|---|
| nginx reverse proxy | `modules/services/proxy/nginx.nix` | TLS via ACME DNS-01 (Cloudflare), wildcard `*.karunagath.in`; per-vhost `nginxAllowCidrs` |
| ACME / cert issuance | `modules/services/infrastructure/acme.nix` | Cloudflare DNS-01, forced to public resolver (1.1.1.1) to dodge Unbound's local redirect zone |
| Authelia (SSO) | `modules/services/infrastructure/authelia.nix` | Own rootless podman user (uid 2301, `modules/users/authelia.nix`); OIDC provider for Grafana/Jellyfin/etc |
| sops-nix secrets | `modules/services/infrastructure/sops.nix` | Age-encrypted, host SSH keys as recipients |
| Homepage dashboard | `modules/services/infrastructure/homepage.nix` | `home.${domain}`; widgets pull live status from most services below |
| OpenSSH | `modules/services/infrastructure/openssh.nix` | LAN-only, key auth only, no root login |
| Tailscale | `modules/services/tailscale.nix` | Exit node + `192.168.1.10/32` subnet route |
| AdGuard Home (DNS+DHCP) | `modules/services/dns/adguard.nix` | `dns.${domain}`; static leases + rewrites for the domain |
| Unbound (recursive resolver) | `modules/services/dns/unbound.nix` | `127.0.0.1:5335`, DoT upstreams (Cloudflare family + Quad9), redirect zone for `${domain}.` |
| PostgreSQL | `modules/services/postgres.nix` | Ghostfolio's DB; listens on all interfaces, scram-sha-256 auth restricted to `br-life` |
| Redis | `modules/services/redis.nix` | Ghostfolio's cache; password-protected, `FLUSHALL` renamed off |
| Podman | `modules/services/virtualisation/podman.nix` | Rootful backend for the quadlet app fleet |
| Arcane (container UI) | `modules/services/virtualisation/arcane.nix` | `oci.${domain}`; own **rootless** podman instance, isolated from the app fleet |
| fail2ban | `modules/fail2ban.nix` | sshd + nginx jails, nftables-multiport ban action |
| Avahi (mDNS reflector) | `modules/services/discovery/avahi.nix` | Relays mDNS between LAN and `ve-media-play` |
| niri (desktop) | `modules/services/niri/default.nix` | Wayland compositor for interactive desktop use; Claude Desktop, gnome-keyring, fcitx5 |
| System tuning | `modules/services/system/{power-tuning,sysadmin,vim,nix-defaults-nixos,nix-allow-unfree,nix-autoupgrade}.nix` | PCI/USB runtime PM, smartd, CLI tooling, nix GC/auto-upgrade policy |

#### NixOS (nspawn) containers

| Container | Defining file | Services inside | Where those are defined |
|---|---|---|---|
| `monitoring` | `modules/containers/monitoring.nix` | Grafana, Prometheus, Loki, Alloy | `modules/services/monitoring/{grafana,prometheus,loki}.nix` |
| `media-play` | `modules/containers/media-play.nix` | Jellyfin, Navidrome | `modules/services/media/players/{jellyfin,navidrome}.nix` |
| `home-auto` | `modules/containers/home-auto.nix` | Frigate/go2rtc (NVR), Zigbee2MQTT, Mosquitto | `modules/services/surveillance/nvr.nix`, `modules/services/home-automation/{zigbee2mqtt,mosquitto}.nix` |

#### Podman quadlet apps (per zone)

**`life` zone (`br-life`)** — `modules/containers/life/*.nix`:

| App | Container file | Service config |
|---|---|---|
| Actual Budget | `life/actualbudget.nix` | `modules/services/finance/actualbudget.nix` |
| Ghostfolio | `life/ghostfolio/ghostfolio.nix` | `modules/services/finance/ghostfolio/{ghostfolio,scraper,backfill}.nix` |

**`media-mgmt` zone (`br-media-mgmt`)** — `modules/containers/media-mgmt/*.nix`,
paired 1:1 with `modules/services/media/acquisition/*.nix` (same basename)
except where noted:

`radarr`, `sonarr`, `lidarr`, `bazarr`, `prowlarr`, `sabnzbd`, `seerr`,
`bookshelf`, `audiobookshelf`, `maintainerr`, `unpackerr`, `recyclarr`,
`aiostreams` (service side: `modules/services/media/streaming/aiostreams.nix`).

**`home-auto` zone (`br-home-auto` + `home-auto-macvlan`)** —
`modules/containers/home-auto/*/default.nix`:

| App | Container file(s) | Service config |
|---|---|---|
| Home Assistant | `home-auto/home-assistant/{container,network,storage,bluetooth,default}.nix` | `modules/services/home-automation/home-assistant/default.nix` + `ha-config/` (YAML, HA's own schema — see root `CLAUDE.md` on validating it) |
| OTBR (Thread border router) | `home-auto/otbr/default.nix` | `modules/services/home-automation/otbr.nix` |
| Matter Server | `home-auto/matter-server/default.nix` | `modules/services/home-automation/matter-server.nix` |
| Music Assistant | `home-auto/music-assistant/default.nix` | `modules/services/home-automation/music-assistant.nix` |
| Wyoming Piper (TTS) | `home-auto/wyoming-piper/default.nix` | `modules/services/home-automation/wyoming-piper.nix` |
| Wyoming Whisper (STT) | `home-auto/wyoming-whisper/default.nix` | `modules/services/home-automation/wyoming-whisper.nix` |

### Logs/metrics → Grafana (sutala-specific)
- Host + all nspawn/podman journald logs ship via each unit's Alloy agent
  (`services-monitoring-alloy-host` on the host;
  `containers-common`/per-app `environment.etc."alloy/*.alloy"` fragments
  inside containers) straight to Loki at
  `10.3.255.2:3100` (the `monitoring` container's veth address).
- Host exporters (node/nginx/unbound/zfs/smartctl/process/systemd) bind to
  `10.3.255.1` and are scraped by Prometheus inside `monitoring`
  (`modules/services/monitoring/prometheus.nix`).
- Grafana (`monitoring` container, `grafana.${domain}`) reads both
  Prometheus and Loki as datasources; dashboards are file-provisioned from
  `modules/services/monitoring/dashboards/*.json`; alert rules/contact point
  (Telegram) are defined in `modules/services/monitoring/grafana.nix`.

---

## `surasa`

### Role
Secondary/off-box DNS resolver (AdGuard Home + Unbound, DoT upstreams),
Snapcast client, and an independent "is sutala up" watchdog — deliberately
placed off sutala so it can alert even if sutala itself is unreachable.
Config: `hosts/surasa/configuration.nix`.

### Hardware
Raspberry Pi 3B+ (aarch64-linux), SD-card boot, wifi-only (`wlan0`,
`192.168.1.39`). No RTC (needs an IP-based NTP bootstrap before DNS is even
up). Weak CPU — always cross-built on `sutala` via `boot.binfmt`, never
built natively; `nixos-raspberrypi` flake input supplies the board profile,
sd-image module, and cachix trust so kernel/firmware doesn't need
QEMU-emulated compilation.

### Network config
Single wifi interface, static-ish IP pinned via a NetworkManager profile
(`ipv4.method = manual`) with a policy-routing rule to avoid asymmetric
routing against the bootstrap ethernet adapter. Own `nftables` firewall;
Tailscale as a plain tailnet member (not an exit node) so it stays SSH-reachable
independent of sutala.

### Services

| Service | Defining file | Notes |
|---|---|---|
| AdGuard Home + Unbound | `modules/services/dns/rpi-secondary.nix` | Secondary resolver; forwards over DoT, same upstream philosophy as sutala's |
| Snapcast client | `modules/services/media/snapclient.nix` | Multi-room audio playback endpoint |
| sutala-watchdog | `modules/services/monitoring/sutala-watchdog.nix` | Plain script+timer pinging sutala; Telegram alert on down (same bot as Grafana's) — not Prometheus-based, deliberately lightweight for 1GB RAM |
| Alloy agent | `modules/services/monitoring/alloy-host.nix` | `lokiUrl` overridden to `https://loki.${domain}/loki/api/v1/push` (nginx vhost) since surasa can't reach the monitoring container's veth directly |
| node-exporter + blackbox-exporter | inline in `hosts/surasa/configuration.nix` | blackbox probes sutala's HTTPS vhosts and DNS from an independent LAN vantage point — see `blackbox-http`/`blackbox-dns` Prometheus jobs below |
| OpenSSH | `modules/services/infrastructure/openssh.nix` | Opened globally (not just LAN if) since first boot/sops-bootstrap happens over a USB ethernet adapter with an unpredictable name |
| sops-nix | `modules/services/infrastructure/sops.nix` | Own age recipient added post-first-boot |

### Logs/metrics → Grafana (surasa-specific)
- Loki push goes over the WAN-routable path — `https://loki.${domain}` (host
  nginx vhost on sutala) — instead of the direct veth address other
  sutala-local services use, since surasa isn't on sutala's internal
  container network.
- Prometheus (running inside sutala's `monitoring` container) scrapes
  surasa's node-exporter and blackbox-exporter directly at
  `192.168.1.39:9100` / `:9115` over the LAN (jobs `node-surasa`,
  `blackbox-http`, `blackbox-dns` in `modules/services/monitoring/prometheus.nix`).
  This is the one cross-host Prometheus scrape in the fleet; everything else
  is scraped from inside sutala.
- surasa-specific alert rules (`surasa-hardware` group — under-voltage) and
  its own Grafana dashboard (`dashboards/surasa.json`) live in
  `modules/services/monitoring/grafana.nix`.

---

## `mac-work`

### Role
Work laptop. nix-darwin manages only shell/nix baseline settings and
Home Manager; no NixOS-style "services" exist on this host — Determinate
owns the actual `nix` daemon (`nix.enable = false` here).
Config: `hosts/mac-work/default.nix`.

### Hardware
aarch64-darwin (Apple Silicon). No hardware-specific modules in this repo
(no disko/hardware-configuration — nix-darwin doesn't manage disk layout).

### Network config
None managed by this repo — no firewall, DNS, or reverse-proxy config here;
it's a client on whatever network it's plugged into.

### Services (Home Manager profiles, user `akarunagath`)

| Profile | Defining file | Content |
|---|---|---|
| `home-profiles-core` | `modules/home/profiles/core.nix` (aggregator) | Baseline dotfiles (git, vim, tmux, etc.) |
| `home-profiles-dev` | `modules/home/profiles/dev.nix` | Dev tooling |
| `home-profiles-shell` | `modules/home/profiles/shell.nix` | Shell config (fzf, zoxide, sesh, ...) |
| `home-shell-default` | `modules/home/shell/default.nix` | Default shell selection |
| `home-work` | `modules/home/work.nix` | `~/.gitconfig.work` include, ripgrep credential-file exclusions — opt-in, mac-work only |

### Logs/metrics → Grafana
None — this host ships nothing to Loki/Prometheus. It's a pure client
machine, not part of the monitoring fleet.

---

## Monitoring & logging pipeline (cross-host detail)

```
sutala host + every nspawn/podman unit's journald
  └─ Alloy agent (per host/container) ─push─> Loki (monitoring container, 10.3.255.2:3100)
surasa host journald
  └─ Alloy agent ─push─> https://loki.${domain} (nginx vhost) ─> same Loki

sutala host exporters (10.3.255.1) ─┐
nspawn container exporters ─────────┤
surasa node/blackbox exporters ─────┼─scrape─> Prometheus (monitoring container, 10.3.255.2:9090)
Home Assistant /api/prometheus ─────┤
Frigate /api/metrics ───────────────┤
Navidrome /metrics ─────────────────┘

Prometheus + Loki ─datasource─> Grafana (monitoring container, grafana.${domain})
Grafana alert rules ─> Telegram bot (contact point defined in grafana.nix)
```

- **Alloy** (`modules/lib/observability.nix: mkAlloyAgent`, wired per-host via
  `modules/services/monitoring/alloy-host.nix` and per-container via
  `modules/containers/common.nix`) tails the full systemd journal as a
  catch-all (`job="systemd-journal"`) plus per-app file/journal sources
  layered on top (e.g. nginx access/error logs via
  `modules/services/proxy/nginx.nix`, Grafana's own log file via
  `modules/services/monitoring/grafana.nix`).
- **Prometheus** scrape jobs (`modules/services/monitoring/prometheus.nix`):
  `prometheus`, `node-host`, `node-surasa`, `node-containers` (monitoring/
  media-play/home-auto node-exporters), `nginx`, `unbound`, `zfs`, `systemd`,
  `smartctl`, `process`, `frigate`, `navidrome`, `homeassistant`,
  `blackbox-http`, `blackbox-dns`. 2-year retention.
- **Loki** (`modules/services/monitoring/loki.nix`): filesystem storage,
  14-day retention, single-node (`replication_factor = 1`).
- **Grafana** (`modules/services/monitoring/grafana.nix`): OIDC login via
  Authelia; dashboards file-provisioned from
  `modules/services/monitoring/dashboards/*.json` (nginx, unbound, zfs,
  logs-overview, system-monitor, system-overview, frigate, smart,
  container-resources, surasa); alert rule groups: `container-health`
  (failed/flapping systemd units), `external-probes` (HTTP/DNS reachability
  + cert expiry, probed from surasa), `host-availability`, `storage-health`
  (ZFS pool state/capacity, SMART), `surasa-hardware` (under-voltage). All
  route to a single Telegram contact point.
- Full network path (which container/veth/bridge each hop crosses) is in
  [`network-diagram.md`](./network-diagram.md#monitoring-and-logging-flow).
