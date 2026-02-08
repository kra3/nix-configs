{ config, inputs, pkgs, lib, ... }:
let
  containerLib = import ../lib { inherit lib config; };
in
{
  networking.firewall = {
    interfaces = {
      ve-media-play = {
        allowedTCPPorts = [
          53 # DNS (if a resolver is enabled in the container)
          4533 # Navidrome
          8095 # Music Assistant
          8096 # Jellyfin
          9100 # node-exporter
        ];
        allowedUDPPorts = [
          53 # DNS (if a resolver is enabled in the container)
          7359 # Jellyfin client discovery
        ];
      };
    };
  };

  containers.media-play = ({
    autoStart = true;
    specialArgs = {
      inherit inputs;
    };
  } // containerLib.container.definition.mkContainerNetwork {
    hostAddress = "10.0.50.5";
    localAddress = "10.0.50.6";
  } // {
    config = {
      imports = [
        ../services/system/nix.nix
        ../containers/common.nix
        ../services/monitoring/agent/alloy.nix
        inputs.declarative-jellyfin.nixosModules.default
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/media/players/server
      ];

      nixpkgs.overlays = [
        inputs.self.overlays.default
      ];

      networking = {
        hostName = "media-play";
        defaultGateway = "10.0.50.5";
        nameservers = [ config.vars.network.lanIp ];
        firewall.allowedTCPPorts = [
          4533 # Navidrome
          8095 # Music Assistant
          8096 # Jellyfin
          1704 # Snapcast audio stream
          1705 # Snapcast control/stream
          1780 # Snapcast JSON API
          9100 # node-exporter
        ];
        firewall.allowedUDPPorts = [
          7359 # Jellyfin client discovery
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
      systemd.tmpfiles.rules = [
        "z /var/lib/jellyfin/log 0750 jellyfin jellyfin - -"
        "z /var/lib/jellyfin/logs 0750 jellyfin jellyfin - -"
        "Z /var/lib/jellyfin/log/*.log 0640 jellyfin jellyfin - -"
        "Z /var/lib/jellyfin/log/*.txt 0640 jellyfin jellyfin - -"
        "Z /var/lib/jellyfin/logs/*.log 0640 jellyfin jellyfin - -"
        "Z /var/lib/jellyfin/logs/*.txt 0640 jellyfin jellyfin - -"
      ];
    };
    bindMounts = {
      "/etc/localtime" = {
        hostPath = "/etc/localtime";
        isReadOnly = true;
      };
      "/dev/dri" = {
        hostPath = "/dev/dri";
        isReadOnly = false;
      };
      "/data" = {
        hostPath = "/srv/media";
        isReadOnly = false;
      };
      "/var/lib/jellyfin" = {
        hostPath = "/srv/appdata/media-play/jellyfin";
        isReadOnly = false;
      };
      "/var/lib/navidrome" = {
        hostPath = "/srv/appdata/media-play/navidrome";
        isReadOnly = false;
      };
      "/var/lib/music-assistant" = {
        hostPath = "/srv/appdata/media-play/music-assistant";
        isReadOnly = false;
      };
      "/run/secrets/media.jellyfin.users.kra3.password" = {
        hostPath = "/run/secrets/media.jellyfin.users.kra3.password";
        isReadOnly = true;
      };
      "/run/secrets/media.jellyfin.users.home.password" = {
        hostPath = "/run/secrets/media.jellyfin.users.home.password";
        isReadOnly = true;
      };
      "/run/secrets/media.jellyfin.apikeys.jellyseerr" = {
        hostPath = "/run/secrets/media.jellyfin.apikeys.jellyseerr";
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
  });

  systemd.services."container@media-play" =
    containerLib.container.definition.mkContainerSystemdDeps [ ];

  # Create jellyfin group on host matching container GID for secret access
  users.groups.jellyfin = {
    gid = 999;
  };

  sops.secrets."media.jellyfin.users.kra3.password" = {
    mode = "0440";
    group = "jellyfin";
  };
  sops.secrets."media.jellyfin.users.home.password" = {
    mode = "0440";
    group = "jellyfin";
  };
  sops.secrets."media.jellyfin.apikeys.jellyseerr" = {
    mode = "0440";
    group = "jellyfin";
  };
}
