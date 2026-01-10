# Monitoring Stack (sutala + container)

```
            ┌─────────────────────────────────────────────┐
LAN Browser │                                             │
───────────▶│ nginx (sutala, 443)                         │
            │  grafana.karunagath.in                      │
            └───────────┬─────────────────────────────────┘
                        │ proxy to container
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
 │ 127.0.0.1:9090               │ 0.0.0.0:3100 │
 └──────┬───────┘               └──────┬───────┘
        │ scrape                         ▲
        │                               │ push
        │   hostAddress 10.0.50.1        │
        ▼                               │
  sutala exporters                       │
  10.0.50.1:9100 node                    │
  10.0.50.1:9113 nginx                   │
  10.0.50.1:9167 unbound                 │
  10.0.50.1:9134 zfs                     │
        ▲                                │
        │                                │
   Alloy (sutala)                         │
   journald -> Loki                       │
                                          │
         container (monitoring) 10.0.50.2    │
```
