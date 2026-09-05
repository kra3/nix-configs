{
  flake.nixosModules.services-monitoring-grafana =
  { config, lib, domain, networkVars, ... }:
  let
    # Known-benign noise excluded from unit-state/restart alerting — scheduled oneshot jobs, unused login/tty scopes, and BlueZ's harmless hci0 reinit cycling (~20x/day, no crash, front-door lock already has a cloud fallback for this).
    noisyUnitsRegex = "(nix-optimise|nixos-rebuild-switch-to-configuration|podman-prune|getty@.+|bluetooth)\\.service";
    # Grafana's auto-generated datasource uid; setting it explicitly via provisioning breaks reconciliation (broke Grafana 2026-09-02) — re-fetch from the API if the DB is ever recreated.
    prometheusDatasourceUid = "PBFA97CFB590B2093";
  in
  {
    services.grafana = {
      enable = true;
      settings = {
        auth = {
          # Works around a Grafana OAuth user-sync bug matching logins to
          # existing accounts by email (grafana#111139).
          oauth_allow_insecure_email_lookup = true;
        };
        security = {
          admin_user = "$__file{/run/secrets/monitoring.grafana.admin.user}";
          admin_password = "$__file{/run/secrets/monitoring.grafana.admin.password}";
          # Preserves the pre-26.05 nixpkgs default so the existing Grafana DB keeps decrypting.
          secret_key = "SW2YcwTIb9zpOOhoPsMm";
        };
        "auth.generic_oauth" = {
          enabled = true;
          allow_sign_up = true;
          name = "Authelia";
          icon = "signin";
          client_id = "grafana";
          client_secret = "$__file{/run/secrets/monitoring.grafana.oidc_client_secret}";
          scopes = "openid profile email groups";
          empty_scopes = false;
          auth_url = "https://auth.${domain}/api/oidc/authorization";
          token_url = "https://auth.${domain}/api/oidc/token";
          api_url = "https://auth.${domain}/api/oidc/userinfo";
          login_attribute_path = "preferred_username";
          email_attribute_path = "email";
          groups_attribute_path = "groups";
          name_attribute_path = "name";
          use_pkce = true;
          # Otherwise Grafana intermittently sends creds via POST body,
          # which Authelia's default (header-based) auth rejects.
          auth_style = "InHeader";
          # Authelia's "admin" group -> Grafana Admin, everyone else Viewer.
          role_attribute_path = "contains(groups[], 'admin') && 'Admin' || 'Viewer'";
        };
        server = {
          http_addr = networkVars.containers.monitoring.localAddress;
          http_port = 3001;
          domain = "grafana.${domain}";
          root_url = "https://grafana.${domain}/";
        };
        analytics.reporting_enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://${networkVars.containers.monitoring.localAddress}:9090";
              isDefault = true;
            }
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://${networkVars.containers.monitoring.localAddress}:3100";
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "default";
              orgId = 1;
              folder = "Sutala";
              type = "file";
              disableDeletion = false;
              editable = false;
              options.path = "/etc/grafana-dashboards";
            }
          ];
        };
        alerting.contactPoints.path = "/run/secrets/monitoring.grafana.telegram_contactpoint.yaml";
        # Root/default route — sole contact point, everything goes to Telegram.
        alerting.policies.settings = {
          apiVersion = 1;
          policies = [
            {
              orgId = 1;
              receiver = "telegram";
              group_by = [ "..." ];
            }
          ];
        };
        alerting.rules.settings = {
          apiVersion = 1;
          groups = [
            {
              orgId = 1;
              name = "container-health";
              folder = "Sutala";
              interval = "1m";
              rules = [
                {
                  uid = "container-failed-state";
                  title = "Systemd unit stuck in failed state";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        # node_exporter's systemd collector runs host-wide and inside every nspawn container, so this covers podman containers, host daemons, and nspawn-internal services automatically.
                        expr = ''node_systemd_unit_state{state="failed", name=~`.+\.service`, name!~`${noisyUnitsRegex}`}'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "gt";
                              params = [ 0 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  # Grace period so a normal deploy-triggered restart doesn't page; only a unit still failed 5m later does.
                  for = "5m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "{{ $labels.name }}{{ if $labels.container }} ({{ $labels.container }}){{ end }} is in a failed state and systemd has stopped retrying it.";
                    description = "Likely hit its memory/CPU cap repeatedly and exceeded systemd's start-rate limit. Needs a manual `systemctl restart` (inside the container, if `container` is set) after checking why — and possibly raising the cap.";
                  };
                  isPaused = false;
                }
                {
                  uid = "container-restart-flapping";
                  title = "Systemd unit restarting repeatedly";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 900;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        # Host-only — doesn't reach nspawn-internal services (still covered by the failed-state alert, just not this early warning); round() avoids increase() false-tripping on a single restart's window-edge extrapolation.
                        expr = ''round(increase(systemd_service_restart_total{name!~`${noisyUnitsRegex}`}[15m]))'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "gt";
                              params = [ 1 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  # Same deploy-noise grace period as container-failed-state.
                  for = "5m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "{{ $labels.name }} has restarted more than once in the last 15 minutes.";
                    description = "Early warning for a possible OOM-restart loop — worth checking before it escalates to the failed-state alert.";
                  };
                  isPaused = false;
                }
              ];
            }
            {
              orgId = 1;
              name = "external-probes";
              folder = "Sutala";
              interval = "1m";
              rules = [
                {
                  uid = "blackbox-http-probe-failed";
                  title = "External HTTP probe failing";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        expr = ''probe_success{job="blackbox-http"}'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "lt";
                              params = [ 1 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "Alerting";
                  execErrState = "Error";
                  # Probed from surasa, scraped by sutala -- a few minutes' grace for transient LAN/wifi blips.
                  for = "5m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "{{ $labels.instance }} HTTP probe (from surasa) is failing.";
                    description = "sutala is reachable (sutala-watchdog would have paged separately if not), but this vhost isn't responding with 2xx -- check nginx, the backend service, and cert validity.";
                  };
                  isPaused = false;
                }
                {
                  uid = "blackbox-dns-probe-failed";
                  title = "DNS resolution failing";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        expr = ''probe_success{job="blackbox-dns"}'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "lt";
                              params = [ 1 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "Alerting";
                  execErrState = "Error";
                  # Same grace as the HTTP probe -- a few minutes for transient LAN/wifi blips before paging.
                  for = "5m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "{{ $labels.instance }} isn't resolving DNS queries.";
                    description = "AdGuard/Unbound process may be up per systemd, but it isn't actually answering -- this breaks internet access for the entire LAN. Check AdGuard's upstream config and Unbound's status.";
                  };
                  isPaused = false;
                }
                {
                  uid = "cert-expiry-soon";
                  title = "TLS certificate expiring soon";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        # Days remaining until the cert seen by the HTTP probe expires.
                        expr = ''(probe_ssl_earliest_cert_expiry_timestamp_seconds{job="blackbox-http"} - time()) / 86400'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "lt";
                              params = [ 14 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  # Slow-changing -- no need for a short grace period, but avoid paging on a single flaky scrape.
                  for = "30m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "{{ $labels.instance }}'s TLS cert expires in under 14 days.";
                    description = "ACME should auto-renew ~30 days out -- if this fires, renewal is silently failing. Check `systemctl status acme-*.service` before it actually expires and breaks the vhost.";
                  };
                  isPaused = false;
                }
              ];
            }
            {
              orgId = 1;
              name = "host-availability";
              folder = "Sutala";
              interval = "1m";
              rules = [
                {
                  uid = "instance-down";
                  title = "Host or container unreachable";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        # node-host/node-surasa are the two physical boxes; node-containers is node_exporter inside each nspawn container -- if any of these goes fully dark, every systemd-unit-state check running on it goes dark too (noData -> OK), so this is the one thing that has to be checked at the up{} level instead.
                        expr = ''up{job=~`node-host|node-surasa|node-containers`}'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "lt";
                              params = [ 1 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  # Same deploy-noise grace period as the other host-level rules -- a nixos-rebuild switch/reboot briefly drops scrapes.
                  for = "5m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "{{ $labels.job }} exporter for {{ $labels.instance }}{{ if $labels.container }} ({{ $labels.container }}){{ end }} is unreachable.";
                    description = "Prometheus can't scrape node_exporter here -- the host/container may be down, hung, or network-partitioned. Every other alert that depends on its systemd data is blind until this clears.";
                  };
                  isPaused = false;
                }
              ];
            }
            {
              orgId = 1;
              name = "storage-health";
              folder = "Sutala";
              interval = "1m";
              rules = [
                {
                  uid = "zfs-pool-degraded";
                  title = "ZFS pool degraded or faulted";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        expr = "zfs_pool_health";
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "gt";
                              params = [ 0 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  # Short grace -- pool state doesn't flap, so 2 evaluations confirming it is enough.
                  for = "2m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "ZFS pool {{ $labels.pool }} is not ONLINE (state={{ $value }}).";
                    description = "0=ONLINE 1=DEGRADED 2=FAULTED 3=OFFLINE 4=UNAVAIL 5=REMOVED 6=SUSPENDED. Run `zpool status {{ $labels.pool }}` -- likely a failed or failing drive.";
                  };
                  isPaused = false;
                }
                {
                  uid = "zfs-pool-capacity-high";
                  title = "ZFS pool nearing capacity";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        expr = "100 * (zfs_pool_allocated_bytes / zfs_pool_size_bytes)";
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "gt";
                              params = [ 85 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  # Capacity moves slowly -- half an hour sustained above threshold rules out a momentary snapshot/scrub spike.
                  for = "30m";
                  labels.severity = "warning";
                  annotations = {
                    summary = "{{ $labels.pool }} is over 85% full.";
                    description = "ZFS write performance and fragmentation both degrade noticeably above ~85% full. Not urgent, but plan cleanup or expansion before it gets there.";
                  };
                  isPaused = false;
                }
                {
                  uid = "disk-smart-failing";
                  title = "Disk failing SMART self-check";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        expr = "smartctl_device_smart_status";
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "lt";
                              params = [ 1 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  for = "5m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "Disk {{ $labels.device }} on {{ $labels.instance }} is failing its SMART health check.";
                    description = "smartctl reports overall-health FAILED -- often an early warning of impending drive failure. Back up data on the affected pool and plan to replace {{ $labels.device }}.";
                  };
                  isPaused = false;
                }
              ];
            }
            {
              orgId = 1;
              name = "surasa-hardware";
              folder = "Sutala";
              interval = "1m";
              rules = [
                {
                  uid = "surasa-undervoltage";
                  title = "Surasa under-voltage detected";
                  condition = "C";
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = prometheusDatasourceUid;
                      model = {
                        refId = "A";
                        expr = ''node_hwmon_in_lcrit_alarm_volts{instance="surasa"}'';
                        instant = true;
                        range = false;
                        intervalMs = 1000;
                        maxDataPoints = 43200;
                      };
                    }
                    {
                      refId = "B";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        expression = "A";
                        reducer = "last";
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "gt";
                              params = [ 0 ];
                            };
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer.type = "last";
                            type = "query";
                          }
                        ];
                        datasource = {
                          type = "__expr__";
                          uid = "__expr__";
                        };
                      };
                    }
                  ];
                  noDataState = "OK";
                  execErrState = "Error";
                  for = "2m";
                  labels.severity = "critical";
                  annotations = {
                    summary = "Surasa's Raspberry Pi is reporting an under-voltage condition.";
                    description = "Common cause of SD-card corruption and random resets on this hardware. Check the power supply and USB cable -- a marginal supply degrades over time.";
                  };
                  isPaused = false;
                }
              ];
            }
          ];
        };
      };
    };

    systemd.services.grafana = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    environment.etc = {
      "grafana-dashboards/nginx.json".source = ./dashboards/nginx.json;
      "grafana-dashboards/unbound.json".source = ./dashboards/unbound.json;
      "grafana-dashboards/zfs.json".source = ./dashboards/zfs.json;
      "grafana-dashboards/logs-overview.json".source = ./dashboards/logs-overview.json;
      "grafana-dashboards/system-monitor.json".source = ./dashboards/system-monitor.json;
      "grafana-dashboards/system-overview.json".source = ./dashboards/system-overview.json;
      "grafana-dashboards/frigate.json".source = ./dashboards/frigate.json;
      "grafana-dashboards/smart.json".source = ./dashboards/smart.json;
      "grafana-dashboards/container-resources.json".source = ./dashboards/container-resources.json;
      "grafana-dashboards/surasa.json".source = ./dashboards/surasa.json;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/grafana 0750 grafana grafana - -"
      "d /var/lib/grafana/data 0750 grafana grafana - -"
      "d /var/lib/grafana/data/log 0750 grafana grafana - -"
    ];

    services.logrotate.settings.grafana = {
      files = [
        "/var/lib/grafana/data/log/*.log"
      ];
      rotate = 1;
      frequency = "hourly";
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      copytruncate = true;
      su = "grafana grafana";
    };

    environment.etc."alloy/grafana.alloy".text = ''
      loki.source.file "grafana" {
        targets = [
          {
            __path__ = "/var/lib/grafana/data/log/grafana.log",
            job = "grafana",
            host = "${config.networking.hostName}",
            role = "${if config.boot.isContainer then "container" else "host"}",
          },
        ]
        forward_to = [loki.write.default.receiver]
      }
    '';
  };
}
