{ config, ... }:
{
  networking.firewall.interfaces = {
    ve-home-auto = {
      allowedTCPPorts = [
        53 # DNS (if a resolver is enabled in the container)
        1883 # Mosquitto
        9100 # node-exporter
      ];
      allowedUDPPorts = [
        53 # DNS (if a resolver is enabled in the container)
      ];
    };
  };

  networking.firewall.interfaces.${config.vars.lanIf}.allowedTCPPorts = [
    1883 # Mosquitto (DNAT to 10.0.50.8)
  ];

  systemd.tmpfiles.rules = [
    "d /srv/appdata/home-auto/mosquitto 0750 root root - -"
  ];

  containers.home-auto = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.7";
    localAddress = "10.0.50.8";
    config = {
      imports = [
        ../nix.nix
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/mosquitto.nix
      ];

      networking = {
        hostName = "home-auto";
        enableIPv6 = false;
        defaultGateway = "10.0.50.7";
        nameservers = [ config.vars.lanIp ];
        useHostResolvConf = false;
        firewall.allowedTCPPorts = [
          1883 # Mosquitto
          9100 # node-exporter
        ];
        firewall.allowedUDPPorts = [
          53 # DNS (if a resolver is enabled in the container)
        ];
        firewall.logRefusedConnections = true;
        firewall.logRefusedPackets = true;
        firewall.logRefusedUnicastsOnly = true;
      };
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/var/lib/mosquitto" = {
        hostPath = "/srv/appdata/home-auto/mosquitto";
        isReadOnly = false;
      };
      "/run/secrets/mqtt.users.kothu.password" = {
        hostPath = "/run/secrets/mqtt.users.kothu.password";
        isReadOnly = true;
      };
    };
  };

  systemd.services."container@home-auto" = {
    requires = [
      "zfs-mount.service"
      "systemd-tmpfiles-resetup.service"
    ];
    after = [
      "zfs-mount.service"
      "systemd-tmpfiles-resetup.service"
    ];
  };

  sops.secrets."mqtt.users.kothu.password" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
