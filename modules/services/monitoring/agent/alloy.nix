{ config, lib, ... }:
let
  roleLabel = if config.boot.isContainer then "container" else "host";
  hasNginx = config.services.nginx.enable;
  hasAdguard = config.services.adguardhome.enable;
  hasJellyfin = config.services.declarative-jellyfin.enable or false;
  containerHosts =
    if config.boot.isContainer then [ ] else lib.attrNames (config.containers or { });
  containerJournalSources = lib.concatMapStringsSep "\n" (name:
    let
      sourceName = lib.replaceStrings [ "-" ] [ "_" ] name;
    in
    ''
    loki.source.journal "systemd_${sourceName}" {
      matches = "_HOSTNAME=${name}"
      labels = {
        job = "systemd-journal",
        host = "${name}",
        role = "container",
      }
      forward_to = [loki.relabel.journal.receiver]
    }
  '') containerHosts;
in
{
  services.alloy = {
    enable = true;
    extraFlags = [
      "--server.http.listen-addr=127.0.0.1:12345"
    ];
  };

  systemd.services.alloy.serviceConfig.SupplementaryGroups = lib.mkAfter (
    lib.optionals (config.users.groups ? media) [ "media" ]
    ++ lib.optionals (config.users.groups ? jellyfin) [ "jellyfin" ]
  );
  systemd.services.alloy.serviceConfig.TimeoutStopSec = "30s";

  environment.etc."alloy/config.alloy".text =
    ''
    loki.write "default" {
      endpoint {
        url = "http://10.0.50.2:3100/loki/api/v1/push"
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
        host = "${config.networking.hostName}",
        role = "${roleLabel}",
      }
    }
    ${containerJournalSources}
    ''
    + lib.optionalString hasNginx ''
    loki.source.file "nginx" {
      targets = [
        {
          __path__ = "/var/log/nginx/*.log",
          job = "nginx",
          host = "${config.networking.hostName}",
          role = "${roleLabel}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
    ''
    + lib.optionalString hasAdguard ''
    loki.source.file "adguardhome" {
      targets = [
        {
          __path__ = "/var/lib/AdGuardHome/data/*.log",
          job = "adguardhome",
          host = "${config.networking.hostName}",
          role = "${roleLabel}",
        },
        {
          __path__ = "/var/lib/AdGuardHome/data/*.json",
          job = "adguardhome",
          host = "${config.networking.hostName}",
          role = "${roleLabel}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
    ''
    + lib.optionalString hasJellyfin ''
    loki.source.file "jellyfin" {
      targets = [
        {
          __path__ = "/var/lib/jellyfin/log/*.log",
          job = "jellyfin",
          host = "${config.networking.hostName}",
          role = "${roleLabel}",
        },
        {
          __path__ = "/var/lib/jellyfin/log/*.txt",
          job = "jellyfin",
          host = "${config.networking.hostName}",
          role = "${roleLabel}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
    '';
}
