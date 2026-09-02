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
    # grafana's in-container gid (dynamically allocated by systemd-sysusers,
    # nixpkgs only pins its uid) turned out to already be 999 on sutala
    # (confirmed via `nixos-container run monitoring -- getent group grafana`)
    # — the same number media-play.nix's jellyfin group already owns on the
    # host, since both containers' independent allocators happened to land
    # on it. Only one group name can own a given gid, so this reuses that
    # existing "jellyfin" host group rather than declaring a second, colliding
    # one; it's not a real jellyfin/grafana relationship, just a coincidence
    # of allocation order in two unrelated containers.
    sops.secrets."monitoring.grafana.admin.user" = lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) {
      mode = "0440";
      group = "jellyfin";
    };
    sops.secrets."monitoring.grafana.admin.password" = lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) {
      mode = "0440";
      group = "jellyfin";
    };
    sops.secrets."monitoring.grafana.oidc_client_secret" = lib.mkIf (config.containers.monitoring.config.services.grafana.enable or false) {
      mode = "0440";
      group = "jellyfin";
    };

    # Create prometheus group on host matching container GID (static, nixpkgs-pinned
    # uid=gid=255) for secret access, same pattern as media-play.nix's jellyfin group.
    users.groups.prometheus = lib.mkIf (config.containers.monitoring.config.services.prometheus.enable or false) {
      gid = 255;
    };

    sops.secrets."homeassistant.token" = lib.mkIf (config.containers.monitoring.config.services.prometheus.enable or false) {
      mode = "0440";
      group = "prometheus";
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
      # Per-cgroup CPU/memory breakdown — groups every process on the host
      # by its full cgroup path, which for a quadlet container is its
      # systemd unit (system.slice/<name>.service). Backs data-driven
      # `Memory=`/`--cpus=` sizing for individual containers; see
      # https://github.com/ncabatoff/process-exporter#using-a-config-file-group-name
      process = {
        enable = true;
        listenAddress = config.vars.network.containers.monitoring.hostAddress;
        settings.process_names = [
          {
            name = "{{.Cgroups}}";
            cmdline = [ ".+" ];
          }
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
        ExecStart = "${pkgs.prometheus-systemd-exporter}/bin/systemd_exporter --web.listen-address=${config.vars.network.containers.monitoring.hostAddress}:9558 --systemd.collector.enable-restart-count";
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
    systemd.services.prometheus-process-exporter = {
      after = [ "container@monitoring.service" "network-online.target" ];
      wants = [ "container@monitoring.service" "network-online.target" ];
      serviceConfig = {
        # Needs to read /proc/<pid>/smaps_rollup for root-owned container
        # processes across every uid, not just its own.
        AmbientCapabilities = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
        CapabilityBoundingSet = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      };
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
          443 # nginx — Grafana's OIDC login calls auth.${domain} directly
          9100 # node-exporter
          9113 # nginx-exporter
          9134 # zfs-exporter
          9167 # unbound-exporter
          9256 # process-exporter
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

        # Pinned to the gid systemd-sysusers already allocated live (confirmed
        # via `getent group grafana` on sutala) -- not a change, just stops it
        # from ever drifting if the container's persistent state is recreated.
        users.groups.grafana.gid = 999;

        networking = {
          hostName = "monitoring";
          defaultGateway = config.vars.network.containers.monitoring.hostAddress;
          nameservers = [ config.vars.network.lanIp ];
          # OIDC login calls auth.${domain} directly; route via the veth
          # host address since the LAN/public IP doesn't route back in.
          extraHosts = "${config.vars.network.containers.monitoring.hostAddress} auth.${config.vars.acme.domain}";
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
        "/run/secrets/monitoring.grafana.oidc_client_secret" = {
          hostPath = "/run/secrets/monitoring.grafana.oidc_client_secret";
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
