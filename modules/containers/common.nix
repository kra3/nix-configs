{ pkgs, lib, config, ... }:
let
  roleLabel = if config.boot.isContainer then "container" else "host";
in
{
  environment.systemPackages = [
    pkgs.vim
  ];

  networking = {
    enableIPv6 = false;
    # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
    useHostResolvConf = lib.mkForce false;
    firewall = {
      logRefusedConnections = true;
      logRefusedPackets = true;
      logRefusedUnicastsOnly = true;
    };
  };

  services.logrotate.enable = true;
  systemd.timers.logrotate.timerConfig.OnCalendar = "*-*-* 00,12:00:00";

  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemMaxFileSize=25M
    MaxRetentionSec=12h
  '';

  time.timeZone = "UTC";
  system.stateVersion = "25.05";

  # Observability: Alloy (log/metrics collection)
  users.groups.alloy = { };
  users.users.alloy = {
    isSystemUser = true;
    group = "alloy";
    extraGroups = lib.mkAfter (
      lib.optionals (config.users.groups ? media) [ "media" ]
      ++ lib.optionals (config.services.declarative-jellyfin.enable or false) [ "jellyfin" ]
      ++ lib.optionals (config.services.nginx.enable or false) [ "nginx" ]
      ++ lib.optionals (config.services.adguardhome.enable or false) [ "adguardhome" ]
      ++ lib.optionals (config.services.radarr.enable or false) [ "radarr" ]
      ++ lib.optionals (config.services.sonarr.enable or false) [ "sonarr" ]
      ++ lib.optionals (config.services.lidarr.enable or false) [ "lidarr" ]
      ++ lib.optionals (config.services.prowlarr.enable or false) [ "prowlarr" ]
      ++ lib.optionals (config.services.bazarr.enable or false) [ "bazarr" ]
      ++ lib.optionals (config.services.sabnzbd.enable or false) [ "sabnzbd" ]
      ++ lib.optionals (config.services.jellyseerr.enable or false) [ "jellyseerr" ]
      ++ lib.optionals (config.services.recyclarr.enable or false) [ "recyclarr" ]
      ++ lib.optionals (config.services.grafana.enable or false) [ "grafana" ]
      ++ lib.optionals (config.services.music-assistant.enable or false) [ "music-assistant" ]
    );
  };

  services.alloy = {
    enable = true;
    extraFlags = [
      "--server.http.listen-addr=127.0.0.1:12345"
      "--disable-reporting"
    ];
  };

  systemd.services.alloy.serviceConfig.TimeoutStopSec = "30s";

  # Note: Alloy (Go binary) requires syscalls not in @system-service set.
  # Skip hardening for now - monitoring agents need flexibility.

  environment.etc."alloy/base.alloy".text = ''
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
  '';

  # Observability: Node Exporter (system metrics)
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
    openFirewall = true;
    enabledCollectors = [ "systemd" ];
  };
}

