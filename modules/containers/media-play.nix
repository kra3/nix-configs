{ inputs, ... }:
{
  networking.firewall = {
    interfaces = {
      ve-media-play = {
        allowedTCPPorts = [
          53
          4533
          8095
          8096
        ];
        allowedUDPPorts = [ 53 ];
      };
    };
  };

  containers.media-play = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.5";
    localAddress = "10.0.50.6";
    config = {
      imports = [
        ../nix.nix
        inputs.declarative-jellyfin.nixosModules.default
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/media/players/server
      ];

      networking = {
        hostName = "media-play";
        enableIPv6 = false;
        defaultGateway = "10.0.50.5";
        nameservers = [ "192.168.1.10" ];
        useHostResolvConf = false;
        firewall.allowedTCPPorts = [
          4533
          8095
          8096
          1704
          1705
          1780
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
        node = "/dev/dri/card0";
        modifier = "rw";
      }
      {
        node = "/dev/dri/renderD128";
        modifier = "rw";
      }
    ];
  };

  sops.secrets."media.jellyfin.users.kra3.password".mode = "0444";
  sops.secrets."media.jellyfin.users.home.password".mode = "0444";
  sops.secrets."media.jellyfin.apikeys.jellyseerr".mode = "0444";
}
