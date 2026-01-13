{ config, ... }:
{
  networking.firewall.interfaces = {
    ve-monitoring = {
      allowedTCPPorts = [
        53 # DNS (if a resolver is enabled in the container)
        9100 # node-exporter
        9113 # nginx-exporter
        9134 # zfs-exporter
        9167 # unbound-exporter
      ];
      allowedUDPPorts = [
        53 # DNS (if a resolver is enabled in the container)
      ];
    };
  };

  containers.monitoring = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.1";
    localAddress = "10.0.50.2";
    config = {
      imports = [
        ../nix.nix
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/monitoring/server
      ];

      networking = {
        hostName = "monitoring";
        enableIPv6 = false;
        defaultGateway = "10.0.50.1";
        nameservers = [ config.vars.lanIp ];
        useHostResolvConf = false;
        firewall.allowedTCPPorts = [
          3001 # Grafana
          3100 # Loki
          9090 # Prometheus
          9100 # node-exporter
        ];
        firewall.logRefusedConnections = true;
        firewall.logRefusedPackets = true;
        firewall.logRefusedUnicastsOnly = true;
      };
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/var/lib/grafana" = {
        hostPath = "/srv/appdata/monitoring/grafana";
        isReadOnly = false;
      };
      "/var/lib/prometheus" = {
        hostPath = "/srv/databases/monitoring/prometheus";
        isReadOnly = false;
      };
      "/var/lib/loki" = {
        hostPath = "/srv/databases/monitoring/loki";
        isReadOnly = false;
      };
      "/run/secrets/monitoring.grafana.admin.user" = {
        hostPath = "/run/secrets/monitoring.grafana.admin.user";
        isReadOnly = true;
      };
      "/run/secrets/monitoring.grafana.admin.password" = {
        hostPath = "/run/secrets/monitoring.grafana.admin.password";
        isReadOnly = true;
      };
    };
  };

  systemd.services."container@monitoring" = {
    requires = [
      "zfs-mount.service"
      "systemd-tmpfiles-resetup.service"
    ];
    after = [
      "zfs-mount.service"
      "systemd-tmpfiles-resetup.service"
    ];
  };
}
