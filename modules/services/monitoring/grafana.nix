{
  flake.nixosModules.services-monitoring-grafana =
  { config, lib, domain, networkVars, ... }:
  let
    # Excluded from unit-state/restart alerting as known-benign noise, not
    # because they're unimportant to the system — scheduled oneshot jobs
    # whose "failed" state just reflects one flaky run (not an ongoing
    # problem) and per-login SSH session scopes/unused ttys, which aren't
    # services at all. Everything else (containers, daemons) alerts by
    # default with no list to maintain.
    noisyUnitsRegex = "(nix-optimise|nixos-rebuild-switch-to-configuration|podman-prune|getty@.+)\\.service";
    # Grafana's own auto-generated datasource uid (from `GET /api/datasources`)
    # — NOT set via provisioning, since giving an already-existing datasource
    # an explicit `uid:` in datasources.settings breaks Grafana's provisioning
    # reconciliation (took the whole service down on 2026-09-02: "Datasource
    # provisioning error: data source not found"). If this Grafana's database
    # is ever wiped/recreated, re-fetch the new uid from the API and update
    # this constant.
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
          # Preserves the pre-26.05 nixpkgs default so the existing Grafana DB
          # (no datasource secrets stored — Prometheus/Loki are unauthenticated,
          # and access is nginx CIDR-allowlisted) keeps decrypting as before.
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
        # Root/default route — sole contact point, so everything goes to
        # Telegram. Revisit with nested `routes:` if per-severity routing
        # (e.g. warning vs critical to different chats) is ever needed.
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
                        # node_exporter's systemd collector runs host-wide and
                        # inside every nspawn container (home-auto, media-play,
                        # monitoring), so restricting to *.service and excluding
                        # known-benign noise (see noisyUnitsRegex) still covers
                        # podman quadlet containers, host daemons, and
                        # nspawn-internal services (frigate, jellyfin, grafana,
                        # etc.) automatically — no per-service list to maintain.
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
                  # Grace period so a normal service restart during a deploy
                  # (nixos-rebuild switch applying a config change) doesn't
                  # page — only a unit still failed 5m later, past systemd's
                  # own start-rate-limit retry window, does.
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
                        # Auto-covers any current or future host-level unit
                        # (host services, podman quadlet containers) with no
                        # list to maintain here, aside from noisyUnitsRegex
                        # (e.g. an unused getty@tty*.service can legitimately
                        # flap without a serial console attached). Doesn't
                        # reach nspawn-internal services (frigate, jellyfin,
                        # etc.) — the dedicated systemd_exporter this metric
                        # comes from only runs on the host; those services
                        # still get the failed-state alert above, just not
                        # this earlier warning. round() avoids a false trip
                        # from a single real restart — increase() extrapolates
                        # near window edges and can read e.g. 1.009 for one
                        # actual restart, which would otherwise clear a bare
                        # `> 1` threshold.
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
