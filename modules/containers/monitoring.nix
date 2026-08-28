{
  flake.nixosModules.containers-monitoring = { config, lib, pkgs, flakeModules, flakeLib, ... }:
  {
    # Host storage for monitoring container
    systemd.tmpfiles.rules = lib.mkMerge [
      [
        "d /srv/appdata/monitoring 0755 root root - -"
        "d /srv/databases/monitoring 0755 root root - -"
      ]
      (lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) [
        "d /srv/appdata/monitoring/grafana 0755 root root - -"
      ])
      (lib.mkIf (config.containers.monitoring.config.services.prometheus.enable or false) [
        "d /srv/databases/monitoring/prometheus 0755 root root - -"
      ])
      (lib.mkIf (config.containers.monitoring.config.services.loki.enable or false) [
        "d /srv/databases/monitoring/loki 0755 root root - -"
      ])
    ];
  
    # Host nginx reverse proxy for Grafana
    services.nginx.virtualHosts."grafana.${config.vars.acme.domain}" = lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) (
      flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${config.vars.network.containers.monitoring.localAddress}:3001";
      }
    );
  
    # Host secrets for monitoring container
    sops.secrets."monitoring.grafana.admin.user" = lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) {
      mode = "0444";
    };
    sops.secrets."monitoring.grafana.admin.password" = lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) {
      mode = "0444";
    };
    sops.secrets."homeassistant.token" = lib.mkIf (config.containers.monitoring.config.services.prometheus.enable or false) {
      mode = "0444";
    };
  
    # Host Prometheus exporters (scraped by monitoring container)
    services.nginx.statusPage = true;
  
    services.prometheus.exporters = {
      node = {
        enable = true;
        listenAddress = config.vars.network.containers.monitoring.hostAddress;
        enabledCollectors = [
          "systemd"
        ];
      };
      smartctl = {
        enable = true;
        listenAddress = config.vars.network.containers.monitoring.hostAddress;
      };
      nginx = {
        enable = true;
        listenAddress = config.vars.network.containers.monitoring.hostAddress;
        scrapeUri = "http://127.0.0.1/nginx_status";
      };
      unbound = {
        enable = true;
        listenAddress = config.vars.network.containers.monitoring.hostAddress;
        unbound.host = "tcp://127.0.0.1:8953";
      };
      zfs = {
        enable = true;
        listenAddress = config.vars.network.containers.monitoring.hostAddress;
        pools = [
          "rpool"
          "tank"
        ];
      };
    };
  
    systemd.services.systemd-exporter = {
      after = [ "container@monitoring.service" "network-online.target" ];
      wants = [ "container@monitoring.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        DynamicUser = true;
        Restart = "always";
        ExecStart = "${pkgs.prometheus-systemd-exporter}/bin/systemd_exporter --web.listen-address=${config.vars.network.containers.monitoring.hostAddress}:9558";
      };
    };
  
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
    systemd.services.prometheus-smartctl-exporter = {
      after = [ "container@monitoring.service" "network-online.target" ];
      wants = [ "container@monitoring.service" "network-online.target" ];
      serviceConfig = {
        SupplementaryGroups = [ "disk" ];
        AmbientCapabilities = [
          "CAP_DAC_READ_SEARCH"
          "CAP_SYS_ADMIN"
          "CAP_SYS_RAWIO"
        ];
        CapabilityBoundingSet = [
          "CAP_DAC_READ_SEARCH"
          "CAP_SYS_ADMIN"
          "CAP_SYS_RAWIO"
        ];
      };
    };
  
    # Host firewall for monitoring container and exporters
    networking.firewall.interfaces = {
      ve-monitoring = {
        allowedTCPPorts = [
          53 # DNS (if a resolver is enabled in the container)
          9100 # node-exporter
          9113 # nginx-exporter
          9134 # zfs-exporter
          9167 # unbound-exporter
          9558 # systemd-exporter
          9633 # smartctl-exporter
        ];
        allowedUDPPorts = [
          53 # DNS (if a resolver is enabled in the container)
        ];
      };
    };
  
    containers.monitoring = ({
      autoStart = true;
      specialArgs = {
        inherit flakeModules;
        domain = config.vars.acme.domain;
        monitoringLocalAddress = config.vars.network.containers.monitoring.localAddress;
        networkVars = config.vars.network;
      };
    } // flakeLib.container-definition.mkContainerNetwork {
      hostAddress = config.vars.network.containers.monitoring.hostAddress;
      localAddress = config.vars.network.containers.monitoring.localAddress;
    } // {
      config = {
        imports = [
          flakeModules.nixos.services-system-nix-defaults-nixos
          flakeModules.nixos.containers-common
          flakeModules.nixos.services-monitoring-default
        ];
  
        networking = {
          hostName = "monitoring";
          defaultGateway = config.vars.network.containers.monitoring.hostAddress;
          nameservers = [ config.vars.network.lanIp ];
          firewall.allowedTCPPorts = [
            3001 # Grafana
            3100 # Loki
            9090 # Prometheus
            9100 # node-exporter
          ];
        };
      };
      bindMounts = {
        "/etc/localtime" = {
          hostPath = "/etc/localtime";
          isReadOnly = true;
        };
        "/var/lib/grafana" = {
          hostPath = "/srv/appdata/monitoring/grafana";
          isReadOnly = false;
        };
        "/var/lib/prometheus2" = {
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
        "/run/secrets/homeassistant.token" = {
          hostPath = "/run/secrets/homeassistant.token";
          isReadOnly = true;
        };
      };
    });
  
    systemd.services."container@monitoring" =
      flakeLib.container-definition.mkContainerSystemdDeps [ ];
  };
}
