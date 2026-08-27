{ lib, ... }:
{
  flake.lib.observability = {
    # Alloy journal-source stanza forwarding one systemd unit's logs to Loki.
    # `id` (the alloy component instance label) defaults to `name` but must be
    # overridden when `name` contains characters River identifiers reject (e.g. "-").
    mkAlloyJournalSource =
      {
        name,
        hostName,
        id ? name,
        unit ? "${name}.service",
        role ? "host",
      }:
      ''
        loki.source.journal "${id}" {
          matches = "_SYSTEMD_UNIT=${unit}"
          labels = {
            job = "${name}",
            host = "${hostName}",
            role = "${role}",
          }
          forward_to = [loki.write.default.receiver]
        }
      '';

    # Enables an Alloy agent (user, service, base.alloy) that pushes to the
    # monitoring stack's Loki and tails the full host/container journal as a
    # catch-all (job="systemd-journal", filterable by the systemd_unit label).
    # Per-app `mkAlloyJournalSource`/file-source fragments layer more specific
    # `job` labels for the same units on top of this.
    mkAlloyAgent =
      {
        hostName,
        monitoringLocalAddress,
        roleLabel ? "host",
        extraGroups ? [ ],
      }:
      {
        users.groups.alloy = { };
        users.users.alloy = {
          isSystemUser = true;
          group = "alloy";
          inherit extraGroups;
        };

        services.alloy = {
          enable = true;
          extraFlags = [
            "--server.http.listen-addr=127.0.0.1:12345"
            "--disable-reporting"
          ];
        };

        systemd.services.alloy.serviceConfig.TimeoutStopSec = "30s";

        environment.etc."alloy/base.alloy".text = ''
          loki.write "default" {
            endpoint {
              url = "http://${monitoringLocalAddress}:3100/loki/api/v1/push"
            }
          }

          loki.relabel "journal" {
            forward_to = [loki.write.default.receiver]
            rule {
              source_labels = ["__journal__UNIT"]
              target_label = "systemd_unit"
            }
            rule {
              source_labels = ["__journal__SYSLOG_IDENTIFIER"]
              target_label = "syslog_identifier"
            }
            rule {
              source_labels = ["__journal__COMM"]
              target_label = "comm"
            }
          }

          loki.source.journal "systemd" {
            forward_to = [loki.relabel.journal.receiver]
            labels = {
              job = "systemd-journal",
              host = "${hostName}",
              role = "${roleLabel}",
            }
          }
        '';
      };
  };
}
