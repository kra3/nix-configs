{ config, ... }:
{
  services.nginx.statusPage = true;

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    globalConfig = {
      scrape_interval = "15s";
    };
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = [ "127.0.0.1:9090" ];
          }
        ];
      }
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "127.0.0.1:9100" ];
          }
        ];
      }
      {
        job_name = "nginx";
        static_configs = [
          {
            targets = [ "127.0.0.1:9113" ];
          }
        ];
      }
      {
        job_name = "unbound";
        static_configs = [
          {
            targets = [ "127.0.0.1:9167" ];
          }
        ];
      }
      {
        job_name = "zfs";
        static_configs = [
          {
            targets = [ "127.0.0.1:9134" ];
          }
        ];
      }
    ];
  };

  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
    nginx = {
      enable = true;
      listenAddress = "127.0.0.1";
      scrapeUri = "http://127.0.0.1/nginx_status";
    };
    unbound = {
      enable = true;
      listenAddress = "127.0.0.1";
      unbound.host = "tcp://127.0.0.1:8953";
    };
    zfs = {
      enable = true;
      listenAddress = "127.0.0.1";
      pools = [
        "rpool"
        "tank"
      ];
    };
  };
}
