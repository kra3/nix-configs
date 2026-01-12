# Network Diagram (sutala)

This reflects the current Nix configuration in `hosts/sutala/configuration.nix`
and `modules/`. Only explicitly configured/open ports are listed.

## Topology

```
LAN 192.168.1.0/24
  |
  | 192.168.1.1 (router / gateway)
  |
  |---- client(s) 192.168.1.x
  |
  |---- sutala (host)
        enp2s0: 192.168.1.10
        |
        |-- reverse proxy (nginx on host)
        |     - dns.karunagath.in        -> 127.0.0.1:3000 (TCP)
        |     - grafana.karunagath.in    -> 10.0.50.2:3001 (TCP)
        |     - jellyfin.karunagath.in   -> 10.0.50.6:8096 (TCP)
        |     - navidrome.karunagath.in  -> 10.0.50.6:4533 (TCP)
        |     - mass.karunagath.in       -> 10.0.50.6:8095 (TCP)
        |     - radarr.karunagath.in     -> 10.0.50.4:7878 (TCP)
        |     - sonarr.karunagath.in     -> 10.0.50.4:8989 (TCP)
        |     - prowlarr.karunagath.in   -> 10.0.50.4:9696 (TCP)
        |     - sabnzbd.karunagath.in    -> 10.0.50.4:8080 (TCP)
        |     - bazarr.karunagath.in     -> 10.0.50.4:6767 (TCP)
        |     - lidarr.karunagath.in     -> 10.0.50.4:8686 (TCP)
        |     - jellyseerr.karunagath.in -> 10.0.50.4:5055 (TCP)
        |
        |-- ve-monitoring (veth)
        |     hostAddress: 10.0.50.1
        |     localAddress: 10.0.50.2  (container "monitoring")
        |
        |-- ve-media-mgmt (veth)
        |     hostAddress: 10.0.50.3
        |     localAddress: 10.0.50.4  (container "media-mgmt")
        |
        |-- ve-media-play (veth)
              hostAddress: 10.0.50.5
              localAddress: 10.0.50.6  (container "media-play")
```

## Interfaces and IPs

- Host:
  - `enp2s0` -> `192.168.1.10`
  - `ve-monitoring` -> `10.0.50.1`
  - `ve-media-mgmt` -> `10.0.50.3`
  - `ve-media-play` -> `10.0.50.5`
- Containers:
  - `monitoring` -> `10.0.50.2`
  - `media-mgmt` -> `10.0.50.4`
  - `media-play` -> `10.0.50.6`

## Routing and NAT

- Host NAT:
  - `externalInterface = enp2s0`
  - `internalInterfaces = [ "ve-monitoring" "ve-media-mgmt" "ve-media-play" ]`
- Container gateways:
  - `monitoring` -> `10.0.50.1`
  - `media-mgmt` -> `10.0.50.3`
  - `media-play` -> `10.0.50.5`
- Container DNS:
  - `nameservers = [ 192.168.1.10 ]`

## WAN Ingress/Egress

- No WAN interface is defined in the repo. Any WAN exposure is controlled by
  the router; `enp2s0` is configured as a LAN interface.

## DNS Flow

```
LAN client -> AdGuard Home (192.168.1.10:53)
AdGuard Home -> Unbound (127.0.0.1:5335)
Unbound -> DoT upstreams (1.1.1.1:853, 9.9.9.11:853)
```

- AdGuard Home:
  - DNS: `192.168.1.10:53` (TCP/UDP) and `127.0.0.1:53`
  - HTTPS UI: `127.0.0.1:3001` (TCP), proxied via `dns.karunagath.in`
  - DoH: `https://dns.karunagath.in/dns-query` (nginx -> 127.0.0.1:3001)
  - Note: AdGuard UI may show `https://dns.karunagath.in:3001/dns-query`, but LAN clients must use the nginx URL on 443.
- Unbound:
  - DNS: `127.0.0.1:5335` (TCP/UDP)
  - Remote control: `127.0.0.1:8953` (TCP)

## Reverse Proxy (nginx)

- Nginx terminates TLS using ACME DNS-01 (Cloudflare).
- All vhosts are LAN-only (`allow 192.168.1.0/24; deny all;`).
- Upstreams are private container IPs (10.0.50.x) or localhost for AdGuard.

## Services and Ports

### Host services

- OpenSSH: `22/tcp` (LAN only)
- Nginx: `443/tcp` (LAN only)
- AdGuard DNS: `53/tcp`, `53/udp` (LAN only)
- Avahi mDNS reflector: `5353/udp` (LAN + `ve-media-play`)
- SSDP relay (multicast-relay): `1900/udp` between `enp2s0` and `ve-media-play`
- Exporters (host bound to `10.0.50.1`, scraped by Prometheus in the monitoring container):
  - Node exporter: `9100/tcp`
  - Nginx exporter: `9113/tcp`
  - ZFS exporter: `9134/tcp`
  - Unbound exporter: `9167/tcp`

### Container: monitoring (10.0.50.2)

- Grafana: `3001/tcp`
- Loki: `3100/tcp`
- Prometheus: `9090/tcp`
- Node exporter: `9100/tcp`
- DNS (if enabled inside container): `53/tcp`, `53/udp`

### Container: media-play (10.0.50.6)

- Jellyfin: `8096/tcp`
- Jellyfin discovery: `7359/udp` (broadcast)
- Music Assistant: `8095/tcp`
- Navidrome: `4533/tcp`
- Snapcast: `1704/tcp`, `1705/tcp`, `1780/tcp`
- Node exporter: `9100/tcp`
- DNS (if enabled inside container): `53/tcp`, `53/udp`

### Container: media-mgmt (10.0.50.4)

- Radarr: `7878/tcp`
- Sonarr: `8989/tcp`
- Prowlarr: `9696/tcp`
- Sabnzbd: `8080/tcp`
- Bazarr: `6767/tcp`
- Lidarr: `8686/tcp`
- Jellyseerr: `5055/tcp`
- Node exporter: `9100/tcp`
- DNS (if enabled inside container): `53/tcp`, `53/udp`

## Discovery and Multicast

- mDNS:
  - Multicast: `224.0.0.251:5353` (IPv4)
  - Avahi reflector on host for `enp2s0` and `ve-media-play`
  - Firewall allows `5353/udp` on both interfaces
- SSDP/UPnP:
  - Multicast: `239.255.255.250:1900` (IPv4)
  - Not explicitly relayed/forwarded in config
- Jellyfin client discovery:
  - Broadcast UDP `:7359` (client-side discovery)

## Monitoring and Logging Flow

```
host+containers journals -> Alloy (host) -> Loki (10.0.50.2:3100) -> Grafana
```

- Alloy runs on host and:
  - Scrapes host journal.
  - Scrapes container journals via `_HOSTNAME=<container>`.
  - Optionally tails nginx/adguardhome/jellyfin files when enabled on host.
- Loki runs in `monitoring` container.
- Grafana runs in `monitoring` container and is proxied via nginx.

## Firewall Allowlist Summary (host)

- `enp2s0` (LAN):
  - `22/tcp`, `53/tcp`, `53/udp`, `443/tcp`, `5353/udp`
- `ve-monitoring`:
  - `9100/tcp`, `9113/tcp`, `9134/tcp`, `9167/tcp`
- `ve-media-mgmt`:
  - `53/tcp`, `53/udp`, `9100/tcp`
- `ve-media-play`:
  - `53/tcp`, `53/udp`, `5353/udp`, `7359/udp`, `4533/tcp`, `8095/tcp`,
    `8096/tcp`, `9100/tcp`
