{ ... }:
{
  services.nginx.statusPage = true;

  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "10.0.50.1";
      enabledCollectors = [ "systemd" ];
    };
    nginx = {
      enable = true;
      listenAddress = "10.0.50.1";
      scrapeUri = "http://127.0.0.1/nginx_status";
    };
    unbound = {
      enable = true;
      listenAddress = "10.0.50.1";
      unbound.host = "tcp://127.0.0.1:8953";
    };
    zfs = {
      enable = true;
      listenAddress = "10.0.50.1";
      pools = [
        "rpool"
        "tank"
      ];
    };
  };

  networking.firewall.interfaces.ve-monitoring.allowedTCPPorts = [
    9100
    9113
    9134
    9167
  ];

  systemd.services.prometheus-node-exporter = {
    after = [ "container@monitoring.service" "network-online.target" ];
    wants = [ "container@monitoring.service" "network-online.target" ];
  };
  systemd.services.prometheus-nginx-exporter = {
    after = [ "container@monitoring.service" "network-online.target" ];
    wants = [ "container@monitoring.service" "network-online.target" ];
  };
  systemd.services.prometheus-unbound-exporter = {
    after = [ "container@monitoring.service" "network-online.target" ];
    wants = [ "container@monitoring.service" "network-online.target" ];
  };
  systemd.services.prometheus-zfs-exporter = {
    after = [ "container@monitoring.service" "network-online.target" ];
    wants = [ "container@monitoring.service" "network-online.target" ];
  };
}
