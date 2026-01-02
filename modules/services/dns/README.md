
### DNS resolution 

```
  LAN Clients
     |
     |  DNS (53), DHCP (67/68)
     v
  AdGuard Home (sutala:<lanIp>)
     - DNS filtering + DHCP
     - Static leases + rewrites for karunagath.in
     |
     |  upstream DNS (127.0.0.1:5335)
     v
  Unbound (localhost on sutala)
     - Recursive resolver + cache
     - DoT upstreams (Cloudflare + Quad9)
```

### Web UI:

```
  Browser (LAN) -> https://dns.karunagath.in
                       |
                       v
                   Nginx (sutala)
                       |
                       v
              AdGuard Home UI (127.0.0.1:3000)
```
