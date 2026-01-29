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
    additionalCapabilities = [ "CAP_PERFMON" ];
    extraFlags = [ "--system-call-filter=perf_event_open" ];
    config = {
      imports = [
        ../nix.nix
        ../containers/common.nix
        ../services/monitoring/agent/alloy.nix
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/mosquitto.nix
        ../services/surveillance
      ];

      networking = {
        hostName = "home-auto";
        defaultGateway = "10.0.50.7";
        nameservers = [ config.vars.lanIp ];
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
      };

      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-compute-runtime-legacy1
          intel-media-driver
          # intel-vaapi-driver
          level-zero
          intel-media-sdk
        ];
      };

    };
    bindMounts = {
      "/dev/dri" = {
        hostPath = "/dev/dri";
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
      "/var/lib/mosquitto" = {
        hostPath = "/srv/appdata/home-auto/mosquitto";
        isReadOnly = false;
      };
      "/run/secrets/mqtt.password" = {
        hostPath = "/run/secrets/mqtt.password";
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
      "/run/secrets/surveillance-nvr-go2rtc.env" = {
        hostPath = config.sops.templates."surveillance-nvr-go2rtc.env".path;
        isReadOnly = true;
      };
      "/run/secrets/surveillance-nvr-frigate.env" = {
        hostPath = config.sops.templates."surveillance-nvr-frigate.env".path;
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

  sops.templates."surveillance-nvr-go2rtc.env" = {
    owner = "root";
    group = "root";
    mode = "0400";
    content = ''
      RANGER_DUO_USER=${config.sops.placeholder."surveillance.go2rtc.ranger_duo.user"}
      RANGER_DUO_PASSWORD=${config.sops.placeholder."surveillance.go2rtc.ranger_duo.password"}
      RANGER_UNO_USER=${config.sops.placeholder."surveillance.go2rtc.ranger_uno.user"}
      RANGER_UNO_PASSWORD=${config.sops.placeholder."surveillance.go2rtc.ranger_uno.password"}
    '';
  };

  sops.templates."surveillance-nvr-frigate.env" = {
    owner = "root";
    group = "root";
    mode = "0400";
    content = ''
      FRIGATE_MQTT_USER=${config.sops.placeholder."mqtt.user"}
      FRIGATE_MQTT_PASSWORD=${config.sops.placeholder."mqtt.password"}
      FRIGATE_RANGER_DUO_USER=${config.sops.placeholder."surveillance.go2rtc.ranger_duo.user"}
      FRIGATE_RANGER_DUO_PASSWORD=${config.sops.placeholder."surveillance.go2rtc.ranger_duo.password"}
      FRIGATE_RANGER_UNO_USER=${config.sops.placeholder."surveillance.go2rtc.ranger_uno.user"}
      FRIGATE_RANGER_UNO_PASSWORD=${config.sops.placeholder."surveillance.go2rtc.ranger_uno.password"}
    '';
  };

  sops.secrets."mqtt.password" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."mqtt.user" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."surveillance.go2rtc.ranger_duo.password" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."surveillance.go2rtc.ranger_duo.user" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."surveillance.go2rtc.ranger_uno.password" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."surveillance.go2rtc.ranger_uno.user" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
