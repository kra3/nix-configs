{ config, pkgs, lib, inputs, ... }:
{
  networking.firewall.interfaces = {
    ve-home-auto = {
      allowedTCPPorts = [
        53 # DNS (if a resolver is enabled in the container)
        80 # Frigate nginx
        8123 # Home Assistant
        8080 # Zigbee2MQTT UI
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

  networking.firewall.interfaces.${config.vars.network.lanIf} = {
    allowedTCPPorts = [
      1883 # Mosquitto (DNAT to 10.0.50.8)
      8555 # go2rtc WebRTC (DNAT to 10.0.50.8)
    ];
    allowedUDPPorts = [
      8555 # go2rtc WebRTC (DNAT to 10.0.50.8)
    ];
  };

  users.groups.frigate = {
    gid = 2100;
  };
  users.groups.zigbee2mqtt = {
    gid = config.ids.gids.zigbee2mqtt;
  };
  services.udev.extraRules = ''
    SUBSYSTEM=="tty", ENV{ID_SERIAL}=="Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_3c705f2672d9ee119f42b74c37b89984", SYMLINK+="zigbee"
  '';

  systemd.tmpfiles.rules = [
    "d /srv/appdata/home-auto/mosquitto 0750 root root - -"
    "d /srv/appdata/home-auto/frigate 2770 root frigate - -"
    "d /srv/appdata/home-auto/go2rtc 0750 root root - -"
    "d /srv/appdata/home-auto/home-assistant 0750 root root - -"
    "d /srv/appdata/home-auto/zigbee2mqtt 2770 root zigbee2mqtt - -"
    "d /srv/surveillance/recordings 2770 root frigate - -"
    "d /srv/surveillance/clips 2770 root frigate - -"
  ];

  containers.home-auto = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.7";
    localAddress = "10.0.50.8";
    additionalCapabilities = [ "CAP_PERFMON" ];
    extraFlags = [ "--system-call-filter=perf_event_open" ];
    specialArgs = {
      inherit inputs;
    };
    config = {
      imports = [
        ../services/system/nix.nix
        ../containers/common.nix
        ../services/monitoring/agent/alloy.nix
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/home-assistant.nix
        ../services/mosquitto.nix
        ../services/surveillance
        ../services/zigbee2mqtt.nix
      ];

      networking = {
        hostName = "home-auto";
        defaultGateway = "10.0.50.7";
        nameservers = [ config.vars.network.lanIp ];
        firewall.allowedTCPPorts = [
          80 # Frigate nginx
          8123 # Home Assistant
          8080 # Zigbee2MQTT UI
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

      services.home-assistant.package =
        inputs.nixpkgs-unstable.legacyPackages.${pkgs.system}.home-assistant;

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
      "/var/lib/home-assistant" = {
        hostPath = "/srv/appdata/home-auto/home-assistant";
        isReadOnly = false;
      };
      "/var/lib/home-assistant/secrets.yaml" = {
        hostPath = config.sops.templates."home-assistant-secrets.yaml".path;
        isReadOnly = true;
      };
      "/var/lib/zigbee2mqtt" = {
        hostPath = "/srv/appdata/home-auto/zigbee2mqtt";
        isReadOnly = false;
      };
      "/dev/zigbee" = {
        hostPath = "/dev/zigbee";
        isReadOnly = false;
      };
      "/run/secrets/mqtt.password" = {
        hostPath = "/run/secrets/mqtt.password";
        isReadOnly = true;
      };
      "/run/secrets/zigbee2mqtt.env" = {
        hostPath = config.sops.templates."zigbee2mqtt.env".path;
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
      {
        node = "/dev/zigbee";
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
    serviceConfig.ExecStartPre = lib.mkAfter [
      "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do [ -e /dev/zigbee ] && exit 0; sleep 1; done; exit 1'"
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

  sops.templates."zigbee2mqtt.env" = {
    owner = "root";
    group = "root";
    mode = "0400";
    content = ''
      ZIGBEE2MQTT_CONFIG_MQTT_USER=${config.sops.placeholder."mqtt.user"}
      ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=${config.sops.placeholder."mqtt.password"}
      ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=${config.sops.placeholder."zigbee2mqtt.frontend.auth_token"}
    '';
  };

  sops.templates."home-assistant-secrets.yaml" = {
    owner = "root";
    group = "root";
    mode = "0444";
    content = ''
      homeassistant_latitude: ${config.sops.placeholder."homeassistant.latitude"}
      homeassistant_longitude: ${config.sops.placeholder."homeassistant.longitude"}
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

  sops.secrets."homeassistant.latitude" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.secrets."homeassistant.longitude" = {
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

  sops.secrets."zigbee2mqtt.frontend.auth_token" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
