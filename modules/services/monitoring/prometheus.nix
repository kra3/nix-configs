{
  flake.nixosModules.services-monitoring-prometheus =
  { networkVars, domain, ... }:
  let
    hostAddr = networkVars.containers.monitoring.hostAddress;
    monAddr = networkVars.containers.monitoring.localAddress;
    mediaAddr = networkVars.containers.mediaPlay.localAddress;
    haAddr = networkVars.containers.homeAuto.localAddress;
  in
  {
    services.prometheus = {
      enable = true;
      checkConfig = false; # Disable build-time validation (secrets not available at build time)
      listenAddress = monAddr;
      port = 9090;
      retentionTime = "2y";
      globalConfig = {
        scrape_interval = "30s";
      };
      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "${monAddr}:9090" ];
              labels.instance = "monitoring";
            }
          ];
        }
        {
          job_name = "node-host";
          static_configs = [
            {
              targets = [ "${hostAddr}:9100" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "node-surasa";
          static_configs = [
            {
              targets = [ "192.168.1.39:9100" ];
              labels.instance = "surasa";
            }
          ];
        }
        {
          job_name = "node-containers";
          static_configs = [
            {
              targets = [ "${monAddr}:9100" ];
              labels.container = "monitoring";
              labels.instance = "monitoring";
            }
            {
              targets = [ "${mediaAddr}:9100" ];
              labels.container = "media-play";
              labels.instance = "media-play";
            }
            {
              targets = [ "${haAddr}:9100" ];
              labels.container = "home-auto";
              labels.instance = "home-auto";
            }
          ];
        }
        {
          job_name = "nginx";
          static_configs = [
            {
              targets = [ "${hostAddr}:9113" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "unbound";
          static_configs = [
            {
              targets = [ "${hostAddr}:9167" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "zfs";
          static_configs = [
            {
              targets = [ "${hostAddr}:9134" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "systemd";
          static_configs = [
            {
              targets = [ "${hostAddr}:9558" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "smartctl";
          static_configs = [
            {
              targets = [ "${hostAddr}:9633" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "process";
          static_configs = [
            {
              targets = [ "${hostAddr}:9256" ];
              labels.instance = "sutala";
            }
          ];
        }
        {
          job_name = "frigate";
          metrics_path = "/api/metrics";
          static_configs = [
            {
              targets = [ "${haAddr}:80" ];
              labels.container = "home-auto";
              labels.instance = "home-auto";
            }
          ];
        }
        {
          job_name = "navidrome";
          metrics_path = "/metrics";
          static_configs = [
            {
              targets = [ "${mediaAddr}:4533" ];
              labels.container = "media-play";
              labels.instance = "media-play";
            }
          ];
        }
        {
          # surasa's blackbox exporter probing sutala from an independent LAN vantage point --
          # catches HTTP-level failures (expired cert, backend crashed behind nginx) that
          # sutala-watchdog's plain ICMP check can't see.
          job_name = "blackbox-http";
          metrics_path = "/probe";
          params.module = [ "http_2xx" ];
          static_configs = [
            {
              targets = [ "https://auth.${domain}" ];
              labels.instance = "auth";
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "192.168.1.39:9115";
            }
          ];
        }
        {
          # Same independent-vantage-point idea as blackbox-http, but resolves a real query against
          # sutala's AdGuard -- catches "running but not actually answering" that no unit-state check can see.
          job_name = "blackbox-dns";
          metrics_path = "/probe";
          params.module = [ "dns_udp" ];
          static_configs = [
            {
              targets = [ "192.168.1.10:53" ];
              labels.instance = "adguard-sutala";
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "192.168.1.39:9115";
            }
          ];
        }
        {
          job_name = "homeassistant";
          metrics_path = "/api/prometheus";
          authorization = {
            type = "Bearer";
            credentials_file = "/run/secrets/homeassistant.token";
          };
          static_configs = [
            {
              targets = [ "10.3.2.10:8123" ];
              labels.instance = "ha";
            }
          ];
        }
      ];
    };

    systemd.services.prometheus = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

  };
}
