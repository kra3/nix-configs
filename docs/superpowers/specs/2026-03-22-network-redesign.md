# Network Redesign — sutala

## Problem

The host `sutala` runs services across two container runtimes (NixOS systemd-nspawn and Podman quadlet) on disjoint address spaces:

- NixOS container veth pairs: `10.0.50.0/24`
- Podman bridge subnets: `10.89.{0,1,2}.0/24`

The split is an artefact of when each runtime was introduced. There is no routing relationship between the two; a single supernet should cover all container networks.

Additionally, zero FORWARD rules exist between container network namespaces, which means:

- Alloy (in media-play and home-auto) cannot push logs to Loki (in monitoring)
- Prometheus cannot scrape node-exporters or service metrics across containers
- HA (Podman) cannot reach Frigate, MQTT, Z2M, or go2rtc (NixOS container)

Other problems: stale scrape targets, a dead HA NixOS module import, go2rtc API bound to loopback, stale nginx proxy for RPi HA, HA multi-homed across two zones (L2 bridging risk), and IP addresses scattered across 15+ files with no single source of truth.

## Design Goals

- **Security**: Zero-trust between zones. Default deny all inter-zone traffic. Every permitted flow explicitly justified per-port.
- **Operability**: Every NixOS container ships logs to Loki via Alloy. Prometheus scrapes every service. No blind spots.
- **Service connectivity**: Services that need to talk can, on the minimum required port set.
- **Maintainability**: Address plan is coherent, self-documenting, and centralized in `vars.nix`.

## Zone Architecture

The network is organized into security zones based on service function, not container runtime. Zone membership determines what a service can reach. Runtime choice (NixOS container vs Podman quadlet) is orthogonal — determined by stability/update lifecycle requirements. All configs remain declarative regardless of runtime.

### Host — Trusted Core (Management Plane)

The host is the trusted core. All host-level services share one trust boundary. It runs shared infrastructure: PostgreSQL, Redis, nginx reverse proxy, AdGuard DNS, Unbound, and the monitoring stack (process-isolated in a NixOS container but at the same network trust tier — it has FORWARD rules to reach all zones).

### Application Zones

| Zone | Services | Trust | Rationale |
|------|----------|-------|-----------|
| **iot** | Frigate, MQTT, Z2M, go2rtc (NixOS container) + HA (Podman, single-homed) | Low trust | IoT devices, cameras, externally-sourced firmware. HA single-homed here — no L2 bridging to other zones. |
| **media** | Jellyfin, Navidrome, MusicAssistant (NixOS container) + arr stack (Podman) | Standard | Media consumption and management. |
| **life** | Ghostfolio, ActualBudget (Podman) | Standard | Personal life management apps. Host DB access via INPUT. |

### Security Policy

- **Default**: DENY all inter-zone traffic.
- **Permitted flows**: Each requires a documented functional dependency and is allowed on minimum required ports only.
- **Stateful**: `ct state established,related accept` handles return traffic. Only the initiating direction needs an explicit rule.
- **Host access**: Zones reach host services (PostgreSQL, Redis, DNS) via INPUT rules on the host-side interface, not FORWARD rules.
- **Podman ingress**: Podman containers publish to `127.0.0.1` — nginx reaches them via localhost. No bridge routing needed for reverse proxy ingress.

## Subnet Plan

All container networks move under `10.3.0.0/16`:

```
10.3.0.0/16          unified container space

Zone: life
└── 10.3.0.0/24      br-life         Ghostfolio, ActualBudget

Zone: media
├── 10.3.1.0/24      br-media-mgmt   arr stack (Podman)
└── 10.3.255.4/30    ve-media-play   Jellyfin, Navidrome, MusicAssistant (NixOS)
                     host .5 ↔ container .6

Zone: iot
├── 10.3.2.0/24      br-home-auto    HA (Podman, single-homed, ip=10.3.2.10)
└── 10.3.255.8/30    ve-home-auto    Frigate, MQTT, Z2M, go2rtc (NixOS)
                     host .9 ↔ container .10

Management plane
└── 10.3.255.0/30    ve-monitoring   Prometheus, Loki, Grafana (NixOS)
                     host .1 ↔ container .2
```

**Why /30**: Each veth link has exactly two endpoints. `/30` makes the point-to-point intent explicit.

**Why 255.x**: Veth links occupy the high end of the `/16`, visually distinct from Podman bridge subnets at the low end.

## vars.nix Centralization

`vars.nix` gains two new option groups under `vars.network`:

```nix
vars.network.containers = {
  monitoring = { hostAddress = "10.3.255.1"; localAddress = "10.3.255.2"; };
  mediaPlay  = { hostAddress = "10.3.255.5"; localAddress = "10.3.255.6"; };
  homeAuto   = { hostAddress = "10.3.255.9"; localAddress = "10.3.255.10"; };
};

vars.network.podmanSubnets = {
  life      = "10.3.0.0/24";
  mediaMgmt = "10.3.1.0/24";
  homeAuto  = "10.3.2.0/24";
};
```

**Host-level modules** (container definitions in `monitoring.nix`, `media-play.nix`, `home-auto.nix`, plus `adguard.nix`, `configuration.nix`, Podman network files) reference `config.vars.network.*` directly.

**Container-scoped modules** (imported inside `containers.*.config` blocks — `common.nix`, `loki.nix`, `grafana.nix`, `prometheus.nix`, `nvr.nix`) cannot access `config.vars` because `config` inside a container refers to the container's own NixOS config, not the host's. These modules receive IPs via `specialArgs`:

- **All NixOS containers** gain `specialArgs.monitoringLocalAddress` (set from `config.vars.network.containers.monitoring.localAddress` at the host level). This is used by `common.nix` for the Alloy → Loki endpoint.
- **Monitoring container** gains `specialArgs.networkVars` (set from `config.vars.network`). This provides `prometheus.nix` with all container IPs for scrape targets, and `loki.nix`/`grafana.nix` with their own bind address.
- **Home-auto container** gains `specialArgs.containerLocalAddress` (set from `config.vars.network.containers.homeAuto.localAddress`). This is used by `nvr.nix` for the Frigate nginx `serverAliases`.

`nginxAllowCidrs` in `configuration.nix` references `vars.network.containers.monitoring.localAddress` instead of a literal `/32`.

## Inter-Zone Traffic Matrix

### FORWARD Rules (default deny, explicit allow)

Every rule below is justified by a functional dependency between services.

| # | From (zone) | Interface | To (zone) | Interface | Ports | Justification |
|---|-------------|-----------|-----------|-----------|-------|---------------|
| 1 | iot | `ve-home-auto` | mgmt | `ve-monitoring` | 3100/tcp | Alloy → Loki (log push) |
| 2 | media | `ve-media-play` | mgmt | `ve-monitoring` | 3100/tcp | Alloy → Loki (log push) |
| 3 | mgmt | `ve-monitoring` | iot | `ve-home-auto` | 80, 9100/tcp | Prometheus → Frigate metrics, node-exporter |
| 4 | mgmt | `ve-monitoring` | media | `ve-media-play` | 4533, 9100/tcp | Prometheus → Navidrome metrics, node-exporter |
| 5 | mgmt | `ve-monitoring` | iot | `br-home-auto` | 8123/tcp | Prometheus → HA metrics endpoint |
| 6 | iot | `br-home-auto` | iot | `ve-home-auto` | 80, 1883, 1984, 5000, 8080/tcp | HA → Frigate, MQTT, go2rtc API, Frigate UI, Z2M |
| 7 | iot | `br-home-auto` | media | `ve-media-play` | 4533, 8095, 8096/tcp | HA → Navidrome, MusicAssistant, Jellyfin |
| 8 | media | `br-media-mgmt` | media | `ve-media-play` | 8096/tcp | arr stack → Jellyfin library refresh |
| 9 | media | `ve-media-play` | iot | `br-home-auto` | 8123/tcp | MusicAssistant → HA (hass provider) |

Rules 6 and 8 are intra-zone (iot→iot, media→media) but still require FORWARD rules because traffic crosses network namespaces through the host.

### Flows NOT Needing FORWARD Rules

| Flow | Why no FORWARD rule |
|------|-------------------|
| `br-life` → host PostgreSQL (5432), Redis (6379) | INPUT rules on `br-life` interface (already in `postgres.nix` / `redis.nix`) |
| nginx → Podman containers | Podman publishes to `127.0.0.1` — localhost, no routing |
| Podman containers → host DNS | Podman's internal DNS handles resolution |
| home-auto container → LAN cameras (192.168.1.21:554, 192.168.1.22:554) | Outbound via host gateway with NAT masquerade (existing config) |
| Arr stack internal wiring (recyclarr → radarr/sonarr) | L2 within `br-media-mgmt` |
| LAN → MQTT (1883), WebRTC (8555) | DNAT port forwarding in `configuration.nix` |

### HA Single-Homing (Change from Current State)

HA is currently multi-homed on both `br-home-auto` and `br-media-mgmt`, making it an L2 bridge between the iot and media zones. This redesign single-homes HA on `br-home-auto` only. HA accesses media services (Jellyfin, Navidrome, MusicAssistant) through FORWARD rule 7 on specific ports, eliminating the L2 bridging risk.

### Podman Container Observability

Alloy runs in NixOS containers only (via `common.nix`). Podman containers (HA, arr stack, life apps) log to host journald. This is existing behavior and not changed by this redesign. If Podman log shipping to Loki is desired in the future, it would be a host-level Alloy/promtail instance shipping journal logs — a host→monitoring INPUT flow, not a FORWARD rule.

## Phases

Five phases, each independently deployable and testable.

### Phase 1 — Stale cleanup

Pure removals. No address changes. Zero risk of service disruption.

**`modules/containers/home-auto.nix`**
- Remove `8123` from `ve-home-auto` host INPUT (`networking.firewall.interfaces.ve-home-auto.allowedTCPPorts`)
- Remove `8123` from container's internal `networking.firewall.allowedTCPPorts`
- Remove `../services/home-assistant.nix` import and associated `services.home-assistant.package` assignment (atomic — import declares the option set the assignment depends on)

**`modules/services/monitoring/prometheus.nix`**
- Remove the `10.0.50.4:9100` scrape target entry (media-mgmt NixOS container, no longer exists)

**`modules/services/home-assistant.nix`**
- Delete file entirely (HA moved to Podman, module had `enable = false`)

**Test:** `nixos-rebuild switch` succeeds. Prometheus UI shows no `10.0.50.4` target. Firewall INPUT rules for `ve-home-auto` no longer list 8123.

### Phase 2 — go2rtc API bind fix

Independent of all address changes.

**`modules/services/surveillance/nvr.nix`**
- `api.listen`: `"127.0.0.1:1984"` → `"0.0.0.0:1984"`

**Test:** After rebuild, from the host: `curl http://10.0.50.8:1984/api` returns a response (host → container via INPUT, which already allows 1984).

### Phase 3 — Podman network renumber + HA single-homing

Renumbers all Podman bridge subnets from `10.89.x` to `10.3.x`. Single-homes HA on `br-home-auto`. NixOS containers are unaffected.

**`modules/vars.nix`**
- Add `vars.network.podmanSubnets` options (life, mediaMgmt, homeAuto with CIDR strings)

**`modules/containers/life/network.nix`**
- `networkConfig.subnets`: `10.89.0.0/24` → reference `config.vars.network.podmanSubnets.life`

**`modules/containers/media-mgmt/network.nix`**
- `networkConfig.subnets`: `10.89.1.0/24` → reference `config.vars.network.podmanSubnets.mediaMgmt`

**`modules/containers/home-auto/home-assistant/network.nix`**
- `networkConfig.subnets`: `10.89.2.0/24` → reference `config.vars.network.podmanSubnets.homeAuto`

**`modules/containers/home-auto/home-assistant/container.nix`**
- Add `ip=10.3.2.10` to home-auto network reference (stable IP for Prometheus scrape in Phase 4)
- Remove `br-media-mgmt` network attachment (HA single-homed on `br-home-auto` only)

**`modules/containers/home-auto/home-assistant/ha-config/configuration.yaml`**
- `trusted_proxies`: `10.89.0.0/16` → `10.3.0.0/16`

**`modules/services/postgres.nix`**
- pg_hba rule: `10.89.0.0/24` → reference `config.vars.network.podmanSubnets.life`

**Test:** After rebuild:
```bash
podman network inspect life       | jq '.[0].subnets'   # 10.3.0.0/24
podman network inspect media-mgmt | jq '.[0].subnets'   # 10.3.1.0/24
podman network inspect home-auto  | jq '.[0].subnets'   # 10.3.2.0/24
podman inspect home-assistant | jq '.[0].NetworkSettings.Networks["home-auto"].IPAddress'  # 10.3.2.10
# HA should NOT be on media-mgmt
podman inspect home-assistant | jq '.[0].NetworkSettings.Networks["media-mgmt"]'  # null
# Ghostfolio can still connect to PostgreSQL
curl -skI https://ghostfolio.karunagath.in
```

**Note:** Phase 3 requires `vars.nix` to have `podmanSubnets` defined. The `vars.network.podmanSubnets` options are added in this phase (not Phase 4).

### Phase 4 — NixOS container renumber + vars + FORWARD rules

All changes in this phase must land in a single `nixos-rebuild switch`. The `vars.network.containers` options are introduced here.

**`modules/vars.nix`**
- Add `vars.network.containers` options (monitoring, mediaPlay, homeAuto with hostAddress/localAddress)

**Container definitions — switch to vars (host-level, can use `config.vars`):**

`modules/containers/monitoring.nix`
- `hostAddress`/`localAddress` → `config.vars.network.containers.monitoring.*`
- `defaultGateway` → `config.vars.network.containers.monitoring.hostAddress`
- 5 exporter `listenAddress` bindings → `config.vars.network.containers.monitoring.hostAddress`
- systemd-exporter `--web.listen-address` → `config.vars.network.containers.monitoring.hostAddress` (currently `0.0.0.0:9558`, hand-rolled systemd unit)
- nginx `proxyPass` for Grafana → `config.vars.network.containers.monitoring.localAddress`

`modules/containers/media-play.nix`
- `hostAddress`/`localAddress` → `config.vars.network.containers.mediaPlay.*`
- `defaultGateway` → `config.vars.network.containers.mediaPlay.hostAddress`
- nginx `proxyPass` for Jellyfin, Navidrome, MusicAssistant → `config.vars.network.containers.mediaPlay.localAddress`

`modules/containers/home-auto.nix`
- `hostAddress`/`localAddress` → `config.vars.network.containers.homeAuto.*`
- `defaultGateway` → `config.vars.network.containers.homeAuto.hostAddress`
- Update DNAT comments to reference new IPs

**Observability (container-scoped modules — use `specialArgs`, not `config.vars`):**

`modules/containers/common.nix`
- Alloy Loki endpoint → `specialArgs.monitoringLocalAddress` (passed to all NixOS containers)

`modules/services/monitoring/loki.nix`
- `http_listen_address` → `specialArgs.networkVars.containers.monitoring.localAddress`
- `instance_addr` → `specialArgs.networkVars.containers.monitoring.localAddress`

`modules/services/monitoring/grafana.nix`
- `http_addr` → `specialArgs.networkVars.containers.monitoring.localAddress`
- datasource URLs → `specialArgs.networkVars.containers.monitoring.localAddress`

`modules/services/monitoring/prometheus.nix`
- `listenAddress` → `specialArgs.networkVars.containers.monitoring.localAddress`
- All scrape targets updated to reference `specialArgs.networkVars`
- HA target: `192.168.1.31:8123` → `10.3.2.10:8123`
- Add Navidrome scrape job (`specialArgs.networkVars.containers.mediaPlay.localAddress`:4533)

`modules/services/media/players/navidrome.nix`
- Add `Prometheus.Enabled = true` to settings

**Routing (host-level, can use `config.vars`):**

`modules/services/dns/adguard.nix`
- DNS rewrite targets → `config.vars.network.containers.*.localAddress`

`modules/services/surveillance/nvr.nix`
- `serverAliases` entry → `specialArgs.containerLocalAddress` (passed to home-auto container)

`hosts/sutala/configuration.nix`
- `nginxAllowCidrs`: `10.0.50.2/32` → `"${config.vars.network.containers.monitoring.localAddress}/32"`
- NAT `forwardPorts` destinations → `config.vars.network.containers.homeAuto.localAddress`
- Add `networking.firewall.extraForwardRules` (9 rules from traffic matrix)

**Test:** After rebuild:
```bash
# Veth addresses reassigned
ip addr show ve-monitoring  # 10.3.255.1
ip addr show ve-media-play  # 10.3.255.5
ip addr show ve-home-auto   # 10.3.255.9

# Container reachability
ping -c1 10.3.255.2   # monitoring
ping -c1 10.3.255.6   # media-play
ping -c1 10.3.255.10  # home-auto

# Logs flowing (Alloy → Loki via FORWARD rules 1,2)
journalctl -u alloy --since "5 min ago"

# Prometheus targets all up
curl -s http://10.3.255.2:9090/api/v1/targets | \
  jq '[.data.activeTargets[] | {job: .labels.job, health: .health}]'

# FORWARD rules active
nft list ruleset | grep -A2 "forward"

# go2rtc API reachable via FORWARD rule 6
curl http://10.3.255.10:1984/api

# No 10.0.50.x or 10.89.x references remaining
grep -r '10\.0\.50\|10\.89\.' modules/ hosts/ --include='*.nix' --include='*.yaml'
```

### Phase 5 — HA nginx cutover

Separate step. Only after `ha2.karunagath.in` has been confirmed stable on Podman HA.

**`modules/services/proxy/nginx.nix`**
- Rename vhost `ha2.karunagath.in` → `ha.karunagath.in`
- Remove stale vhost `ha.karunagath.in → 192.168.1.31:8123` (RPi HA)

**Test:** `curl -skI https://ha.karunagath.in` reaches Podman HA. No traffic to `192.168.1.31`.

## What Does Not Change

| Item | Reason |
|------|--------|
| Veth isolation model | Preserves per-service INPUT chain enforcement |
| `br-life` → host 5432, 6379 INPUT rules | Already correct in `postgres.nix` / `redis.nix` |
| Podman NAT for localhost-published ports | Self-managed by Podman |
| Avahi mDNS (`enp2s0` ↔ `ve-media-play`) | Interface names unchanged |
| Tailscale | No IP changes affect Tailscale routing |
| AdGuard `*.karunagath.in → 192.168.1.10` rewrite | Host LAN IP unchanged |
| Unbound config | No address dependencies |
| arcane / podman default bridge (10.88.0.0/16) | Outside scope |
| `services/surveillance/proxy.nix` | Derives IPs from `config.containers.home-auto.localAddress` at eval time |
| home-auto container → LAN cameras (RTSP) | Outbound NAT masquerade, existing config |
| Podman container logging to host journald | Existing behavior, not a network change |
