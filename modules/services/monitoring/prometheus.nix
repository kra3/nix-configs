{ networkVars, ... }:
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
      scrape_interval = "15s";
    };
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:9090" ];
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

}
