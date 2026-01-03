# Monitoring Stack (sutala)

```
                          ┌──────────────────────────┐
LAN Browser ─────────────▶│ nginx (443)              │
                          │  grafana.karunagath.in   │
                          └───────────┬──────────────┘
                                      │ proxy
                                      ▼
                              ┌─────────────┐
                              │ Grafana     │
                              │ 127.0.0.1:3001
                              └─────┬───────┘
                                    │ datasources
                     ┌──────────────┼───────────────┐
                     ▼                              ▼
              ┌──────────────┐               ┌──────────────┐
              │ Prometheus   │               │ Loki         │
              │ 127.0.0.1:9090               │ 127.0.0.1:3100
              └──────┬───────┘               └──────┬───────┘
                     │ scrape                         ▲
                     │                               │ push
       ┌─────────────┼─────────────┐                 │
       ▼             ▼             ▼                 │
  node-exporter   nginx-exporter  unbound-exporter    │
  127.0.0.1:9100  127.0.0.1:9113  127.0.0.1:9167      │
                     ▲             ▲                  │
                     │             │                  │
              nginx status      unbound control       │
              /nginx_status     tcp://127.0.0.1:8953  │
                                                       │
                         ┌─────────────────────────────┘
                         ▼
                 Alloy (journald)
                 sends systemd logs to Loki
```
