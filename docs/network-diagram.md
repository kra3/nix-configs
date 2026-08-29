# Network Diagram (sutala)

This reflects the current Nix configuration in `hosts/sutala/configuration.nix`
and `modules/`. Only explicitly configured/open ports are listed.

Two different container mechanisms are in play, and they're addressed
differently:

- **NixOS (systemd-nspawn) containers** — `monitoring`, `media-play`,
  `home-auto` — each a full virtual host with its own veth pair, on the
  `10.3.255.0/24` range (`modules/vars.nix`).
- **Podman quadlet apps** — everything under `modules/containers/{life,
  media-mgmt,home-auto/*}` — grouped onto per-zone bridge networks on
  `10.3.{0,1,2}.0/24` (`modules/vars.nix: podmanSubnets`). Their ports are
  published to `127.0.0.1` only (not to the bridge or the LAN interface);
  nginx on the host reaches them over loopback, not their bridge IP.

## Topology

```
LAN 192.168.1.0/24
  |
  | 192.168.1.1 (router / gateway)
  |
  |---- client(s) 192.168.1.x
  |
  |---- sutala (host) — enp2s0: 192.168.1.10
        |
        |-- reverse proxy (nginx on host) -- see "Reverse Proxy" below
        |
        |-- tailscale0 (100.64.0.0/10) -- exit node + subnet route for 192.168.1.10/32
        |
        |-- ve-monitoring (veth) — host 10.3.255.1, container 10.3.255.2 (nspawn "monitoring")
        |-- ve-media-play (veth) — host 10.3.255.5, container 10.3.255.6 (nspawn "media-play")
        |-- ve-home-auto (veth) — host 10.3.255.9, container 10.3.255.10 (nspawn "home-auto")
        |
        |-- br-life (podman, 10.3.0.0/24)
        |     ghostfolio, actualbudget                     (life zone)
        |-- br-media-mgmt (podman, 10.3.1.0/24)
        |     radarr, sonarr, prowlarr, sabnzbd, bazarr, lidarr, seerr,
        |     bookshelf, audiobookshelf, maintainerr, unpackerr, recyclarr
        |-- br-home-auto (podman, 10.3.2.0/24, gw 10.3.2.1)
        |     home-assistant .10, otbr .11, matter-server .12,
        |     music-assistant .13
        |-- home-auto-macvlan (podman, macvlan/bridge on enp2s0, no gateway)
        |     home-assistant 192.168.1.33, otbr 192.168.1.34,
        |     matter-server 192.168.1.35, music-assistant 192.168.1.36
        |     -- direct LAN L2 presence for SSDP/mDNS/Matter discovery;
        |        bypasses host nftables (see Security Notes)
        |
        |-- default podman network (rootful)
              arcane (127.0.0.1:3552) — has /run/podman/podman.sock bind-mounted
        |-- authelia rootless podman (own dedicated user, uid 2301)
              authelia (127.0.0.1:9091)
```

## Interfaces and IPs

- Host: `enp2s0` -> `192.168.1.10`, `tailscale0` -> tailnet address
- nspawn veths: `ve-monitoring` 10.3.255.1, `ve-media-play` 10.3.255.5,
  `ve-home-auto` 10.3.255.9
- nspawn containers: `monitoring` 10.3.255.2, `media-play` 10.3.255.6,
  `home-auto` 10.3.255.10
- Podman bridges: `br-life` 10.3.0.0/24, `br-media-mgmt` 10.3.1.0/24,
  `br-home-auto` 10.3.2.0/24 (gw `10.3.2.1`)
- `home-auto-macvlan`: shares the LAN subnet (192.168.1.0/24) directly via
  `enp2s0`; static IPs 192.168.1.33–36 for home-assistant/otbr/matter-server/
  music-assistant respectively (fixed MACs `02:42:c0:a8:01:21`–`24`)

## Routing and NAT

- Host NAT: `externalInterface = enp2s0`, `internalInterfaces = [
  ve-monitoring, ve-media-play, ve-home-auto ]` (nspawn veths only — the
  podman bridges get their outbound NAT from the explicit `extraForwardRules`
  below, not this list)
- Container gateways: `monitoring` -> 10.3.255.1, `media-play` -> 10.3.255.5,
  `home-auto` (nspawn) -> 10.3.255.9, home-auto pods -> 10.3.2.1
- Container DNS: `nameservers = [ 192.168.1.10 ]` everywhere
- Port forwards (DNAT from LAN to home-auto nspawn container, `10.3.255.10`):
  `1883/tcp` (Mosquitto), `8555/tcp+udp` (go2rtc WebRTC)

### Default-deny FORWARD with explicit inter-zone allows

`hosts/sutala/configuration.nix` sets `filterForward = true` and an explicit
`extraForwardRules` allow-list (nothing crosses a zone boundary unless
listed here):

| # | Flow | Ports |
|---|---|---|
| 1 | monitoring → media-play | 9100 (node-exporter), 4533 (navidrome) |
| 2 | monitoring → home-auto (nspawn) | 9100, 80 (frigate) |
| 3 | monitoring → home-auto pods (br-home-auto) | 8123 (HA prometheus) |
| 4 | home-auto (nspawn) → monitoring | 3100 (loki) |
| 5 | media-play → monitoring | 3100 (loki) |
| 6 | home-auto pods → home-auto (nspawn) | 1883, 5000 (mqtt, frigate) |
| 6a| home-auto (nspawn) → home-auto pods | 1883 (mqtt return traffic) |
| 7 | home-auto (nspawn) → home-auto pods | 8123 (frigate → HA notifications) |
| 8 | home-auto pods → media-play | 8096 (HA → jellyfin) |
| 9 | br-media-mgmt → media-play | 8096 (seerr → jellyfin) |
| 10| LAN → home-auto (nspawn) | 1883, 8555 (DNAT) |
| 11| br-life / br-media-mgmt / br-home-auto → internet | outbound only |

## WAN Ingress/Egress

- No WAN interface is defined in the repo. Any WAN exposure is controlled by
  the router; `enp2s0` is configured as a LAN interface.
- Tailscale advertises this host as an **exit node** and as a subnet route
  for `192.168.1.10/32` — remote tailnet devices can reach it (and, as an
  exit node, egress the internet through it) subject to Tailscale ACLs,
  which live outside this repo.

## DNS Flow

```
LAN/tailnet client -> AdGuard Home (192.168.1.10:53, tailscale IP:53)
AdGuard Home -> Unbound (127.0.0.1:5335)
Unbound -> DoT upstreams (1.1.1.1:853 family, 9.9.9.11:853 quad9)
```

- AdGuard Home:
  - DNS: bound to `127.0.0.1`, `192.168.1.10`, and the host's tailscale IP
    (`53/tcp+udp`)
  - HTTPS UI: `127.0.0.1:3001`, proxied via `dns.${domain}`
  - DoH: `https://dns.${domain}/dns-query`
  - `*.${domain}` rewritten to `192.168.1.10`; `monitoring`/`media-play`/
    `home-auto` rewritten to their nspawn container addresses
- Unbound: `127.0.0.1:5335`, remote control on `127.0.0.1:8953`
- Local zone `${domain}.` is a redirect zone in Unbound; ACME uses
  `1.1.1.1:53` directly for its own zone lookups to avoid that redirect
  swallowing SOA queries

## Reverse Proxy (nginx)

- TLS via ACME DNS-01 (Cloudflare), wildcard cert for `*.${domain}`.
- Vhosts are allowed from `nginxAllowCidrs` — on sutala this is LAN CIDR,
  tailscale CGNAT (`100.64.0.0/10`), loopback, the monitoring container's
  address, and the `br-home-auto` subnet (**not** `br-life`/`br-media-mgmt`
  — apps on those zones reach other vhosts only via loopback-published
  upstreams, not as nginx clients).
- Upstreams: nspawn container IPs for monitoring/media-play, `127.0.0.1:<port>`
  for every podman-quadlet app (published-port pattern above), and the
  `br-home-auto` gateway (`10.3.2.1`) for home-auto pods reaching
  domains pinned via `addHosts`.

### Vhosts

| Vhost | Upstream |
|---|---|
| `dns.${domain}` | `127.0.0.1:3001` (AdGuard) |
| `grafana.${domain}` | `10.3.255.2:3001` (monitoring) |
| `jellyfin.${domain}` | `10.3.255.6:8096` (media-play) |
| `navidrome.${domain}` | `10.3.255.6:4533` (media-play) |
| `ma.${domain}` + `ma-snapcast` (1705) | `127.0.0.1:8095` / `10.3.2.13:1705` (music-assistant) |
| `ha.${domain}` | `127.0.0.1:8123` (home-assistant) |
| `nvr.${domain}` | frigate (home-auto nspawn, port 80) |
| `z2m.${domain}` | zigbee2mqtt (home-auto nspawn, port 8080) |
| `oci.${domain}` | `127.0.0.1:3552` (arcane) |
| `auth.${domain}` | `127.0.0.1:9091` (authelia) |
| `ghostfolio.${domain}` | `127.0.0.1:3333` |
| `actualbudget.${domain}` | `127.0.0.1:5006` |
| `radarr` / `sonarr` / `prowlarr` / `sabnzbd` / `bazarr` / `lidarr` / `seerr` / `bookshelf` / `audiobookshelf` / `maintainerr` `.${domain}` | `127.0.0.1:{7878,8989,9696,8080,6767,8686,5055,8787,13378,6246}` respectively |
| mosquitto stream proxy (`1883`) | `10.3.255.10:1883` (home-auto nspawn, via `services.nginx.streamConfig`) |

## Services and Ports

### Host services

- OpenSSH: `22/tcp` (LAN only; key-auth only, root login disabled)
- Nginx: `443/tcp` (LAN + tailscale CGNAT, per-vhost `nginxAllowCidrs`)
- AdGuard DNS: `53/tcp+udp` (LAN + tailscale)
- Tailscale: `openFirewall = true` (tailscale0 fully open by design)
- Avahi mDNS reflector: `5353/udp` (LAN + `ve-media-play`)
- SSDP relay (multicast-relay): `1900/udp` between `enp2s0` and `ve-media-play`
- Exporters (bound to `10.3.255.1`, scraped by Prometheus in `monitoring`):
  node (`9100`), nginx (`9113`), zfs (`9134`), unbound (`9167`), systemd
  (`9558`), smartctl (`9633`)

### nspawn: monitoring (10.3.255.2)

Grafana `3001`, Loki `3100`, Prometheus `9090`, node-exporter `9100`.

### nspawn: media-play (10.3.255.6)

Jellyfin `8096` (+ discovery UDP `7359`), Navidrome `4533`, node-exporter
`9100`.

### nspawn: home-auto (10.3.255.10)

Frigate UI `5000` + metrics `5001` + nginx `80`, go2rtc UI `1984` + WebRTC
`8555` (DNAT'd from LAN), Zigbee2MQTT UI `8080`, Mosquitto `1883` (DNAT'd
from LAN), node-exporter `9100`.

### br-media-mgmt pods (10.3.1.0/24)

radarr `7878`, sonarr `8989`, prowlarr `9696`, sabnzbd `8080`, bazarr `6767`,
lidarr `8686`, seerr `5055`, bookshelf `8787`, audiobookshelf `13378`→80,
maintainerr `6246`, unpackerr `5656` — all published to `127.0.0.1` only.

### br-life pods (10.3.0.0/24)

ghostfolio `3333`, actualbudget `5006` — published to `127.0.0.1` only;
ghostfolio talks to host-native postgres/redis via `host.containers.internal`.

### br-home-auto + macvlan pods (10.3.2.0/24 / 192.168.1.33-36)

home-assistant `8123`, otbr `8081`, matter-server `5580`, music-assistant
`8095` + snapcast `1704/1705/1780` — loopback-published for nginx, **plus**
a second NIC on `home-auto-macvlan` for LAN-local discovery.

### rootful podman default network

arcane `127.0.0.1:3552` — separately networked from the three zone bridges;
holds `/run/podman/podman.sock` (rootful) bind-mounted in.

### authelia rootless podman (own dedicated user)

authelia `127.0.0.1:9091` — runs under its own dedicated rootless podman
instance (uid 2301, `modules/users/authelia.nix`), separately networked from
the three zone bridges and from arcane's own podman.

## Discovery and Multicast

- mDNS: `224.0.0.251:5353`, Avahi reflector on host for `enp2s0` and
  `ve-media-play`; `home-auto-macvlan` pods get native LAN L2 presence
  instead of relay.
- SSDP/UPnP: `239.255.255.250:1900`, relayed between `enp2s0` and
  `ve-media-play` only (not relayed for home-auto — those pods use macvlan).
- Jellyfin client discovery: broadcast UDP `:7359`.

## Monitoring and Logging Flow

```
host+containers journals -> Alloy (host) -> Loki (10.3.255.2:3100) -> Grafana
```

Alloy scrapes the host journal and container journals (`_HOSTNAME=<name>`);
quadlet apps ship journal entries via per-app `environment.etc."alloy/*.alloy"`
sources. Loki + Grafana run in the `monitoring` nspawn container, proxied via
nginx.

## Security Notes (see full review for detail)

- `home-auto-macvlan` gives 4 pods a real LAN presence that bypasses host
  nftables — traffic to/from other LAN devices doesn't traverse the
  `extraForwardRules` allow-list above.
- Arcane holds the **rootful** podman socket — full host-root equivalent
  from inside that one container.
- SSH: password auth off, root login disabled (`PermitRootLogin = "no"`),
  deploy goes through `kra3` + sudo only.
