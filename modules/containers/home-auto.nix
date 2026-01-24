{ config, pkgs, ... }:
{
  networking.firewall.interfaces = {
    ve-home-auto = {
      allowedTCPPorts = [
        53 # DNS (if a resolver is enabled in the container)
        80 # Frigate nginx
        1883 # Mosquitto
        1984 # go2rtc UI
        8555 # go2rtc WebRTC
        5000 # Frigate UI
        5001 # Frigate metrics
        9100 # node-exporter
      ];
      allowedUDPPorts = [
        53 # DNS (if a resolver is enabled in the container)
        8555 # go2rtc WebRTC
      ];
    };
  };

  networking.firewall.interfaces.${config.vars.lanIf} = {
    allowedTCPPorts = [
      1883 # Mosquitto (DNAT to 10.0.50.8)
      8555 # go2rtc WebRTC (DNAT to 10.0.50.8)
    ];
    allowedUDPPorts = [
      8555 # go2rtc WebRTC (DNAT to 10.0.50.8)
    ];
  };

  systemd.tmpfiles.rules = [
    "d /srv/appdata/home-auto/mosquitto 0750 root root - -"
    "d /srv/appdata/home-auto/frigate 0750 root root - -"
    "d /srv/appdata/home-auto/go2rtc 0750 root root - -"
    "d /srv/surveillance/recordings 0750 root root - -"
    "d /srv/surveillance/clips 0750 root root - -"
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
        ../services/surveillance
      ];

      networking = {
        hostName = "home-auto";
        enableIPv6 = false;
        defaultGateway = "10.0.50.7";
        nameservers = [ config.vars.lanIp ];
        useHostResolvConf = false;
        firewall.allowedTCPPorts = [
          80 # Frigate nginx
          1883 # Mosquitto
          1984 # go2rtc UI
          8555 # go2rtc WebRTC
          5000 # Frigate UI
          5001 # Frigate metrics
          9100 # node-exporter
        ];
        firewall.allowedUDPPorts = [
          53 # DNS (if a resolver is enabled in the container)
          8555 # go2rtc WebRTC
        ];
        firewall.logRefusedConnections = true;
        firewall.logRefusedPackets = true;
        firewall.logRefusedUnicastsOnly = true;
      };
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-compute-runtime
          intel-media-driver
          intel-vaapi-driver
          vpl-gpu-rt
        ];
      };
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/dev/dri" = {
        hostPath = "/dev/dri";
        isReadOnly = false;
      };
      "/media/frigate" = {
        hostPath = "/srv/surveillance";
        isReadOnly = false;
      };
      "/var/lib/frigate" = {
        hostPath = "/srv/appdata/home-auto/frigate";
        isReadOnly = false;
      };
      "/var/lib/frigate/recordings" = {
        hostPath = "/srv/surveillance/recordings";
        isReadOnly = false;
      };
      "/var/lib/frigate/clips" = {
        hostPath = "/srv/surveillance/clips";
        isReadOnly = false;
      };
      "/var/lib/go2rtc" = {
        hostPath = "/srv/appdata/home-auto/go2rtc";
        isReadOnly = false;
      };
      "/var/lib/mosquitto" = {
        hostPath = "/srv/appdata/home-auto/mosquitto";
        isReadOnly = false;
      };
      "/run/secrets/mqtt.users.kothu.password" = {
        hostPath = "/run/secrets/mqtt.users.kothu.password";
        isReadOnly = true;
      };
      "/run/secrets/surveillance.go2rtc.ranger_duo.password" = {
        hostPath = "/run/secrets/surveillance.go2rtc.ranger_duo.password";
        isReadOnly = true;
      };
      "/run/secrets/surveillance.go2rtc.ranger_uno.password" = {
        hostPath = "/run/secrets/surveillance.go2rtc.ranger_uno.password";
        isReadOnly = true;
      };
    };
    allowedDevices = [
      {
        node = "/dev/dri/card1";
        modifier = "rw";
      }
      {
        node = "/dev/dri/renderD128";
        modifier = "rw";
      }
    ];
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
