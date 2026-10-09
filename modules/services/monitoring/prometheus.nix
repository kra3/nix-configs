{
  flake.nixosModules.services-monitoring-prometheus =
    {
      networkVars,
      localMedia,
      domain,
      lib,
      ...
    }:
    let
      hostAddr = networkVars.containers.monitoring.hostAddress;
      monAddr = networkVars.containers.monitoring.localAddress;
      mediaAddr = networkVars.containers.mediaPlay.localAddress;
      haAddr = networkVars.containers.homeAuto.localAddress;
      systemdUnitTrim = [
        {
          source_labels = [
            "__name__"
            "state"
          ];
          regex = "node_systemd_unit_state;(activating|deactivating|inactive)";
          action = "drop";
        }
        {
          source_labels = [
            "__name__"
            "name"
          ];
          regex = "node_systemd_unit_state;.+\\.(socket|target|timer|path|swap)";
          action = "drop";
        }
      ];
    in
    {
      services.prometheus = {
        enable = true;
        checkConfig = false; # Disable build-time validation (secrets not available at build time)
        listenAddress = monAddr;
        port = 9090;
        # HA's own recorder keeps long-term statistics independently of this.
        retentionTime = "180d";
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
            metric_relabel_configs = systemdUnitTrim;
          }
          {
            job_name = "node-surasa";
            static_configs = [
              {
                targets = [ "192.168.1.39:9100" ];
                labels.instance = "surasa";
              }
            ];
            metric_relabel_configs = systemdUnitTrim;
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
            metric_relabel_configs = systemdUnitTrim;
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
            metric_relabel_configs = [
              {
                source_labels = [ "__name__" ];
                regex = "namedprocess_namegroup_(states|context_switches_total|minor_page_faults_total|num_threads|threads_wchan|worst_fd_ratio|oldest_start_time_seconds)";
                action = "drop";
              }
              {
                source_labels = [
                  "__name__"
                  "memtype"
                ];
                regex = "namedprocess_namegroup_memory_bytes;(virtual|proportionalResident|proportionalSwapped)";
                action = "drop";
              }
              {
                source_labels = [ "groupname" ];
                regex = "\\[/user\\.slice/user-1000\\.slice/.*";
                action = "drop";
              }
              # The payload cgroup's hash changes on every container restart.
              {
                source_labels = [ "groupname" ];
                regex = "(.*)/libpod-payload-[0-9a-f]+(.*)";
                target_label = "groupname";
                replacement = "$1/libpod-payload$2";
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
            job_name = "slskd";
            metrics_path = "/metrics";
            static_configs = [
              {
                targets = [ "${networkVars.podmanAddresses.slskd}:5030" ];
                labels.instance = "slskd";
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
            metric_relabel_configs = [
              {
                source_labels = [ "__name__" ];
                regex = "ha_.*_created|ha_last_updated_time_seconds";
                action = "drop";
              }
            ];
          }
        ]
        ++ lib.optionals localMedia.enable [
          {
            job_name = "jellyfin";
            metrics_path = "/metrics";
            static_configs = [
              {
                targets = [ "${mediaAddr}:8096" ];
                labels.container = "media-play";
                labels.instance = "media-play";
              }
            ];
            metric_relabel_configs = [
              {
                source_labels = [ "__name__" ];
                regex = ".*_bucket";
                action = "drop";
              }
            ];
          }
        ]
        ++ lib.optionals (localMedia.enable && localMedia.extras.enable) [
          {
            job_name = "unpackerr";
            metrics_path = "/metrics";
            static_configs = [
              {
                targets = [ "${networkVars.podmanAddresses.unpackerr}:5656" ];
                labels.instance = "unpackerr";
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
