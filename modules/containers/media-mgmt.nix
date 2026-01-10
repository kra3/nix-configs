{ config, ... }:
{
  networking.firewall.interfaces = {
    ve-media-mgmt = {
      allowedTCPPorts = [
        53 # DNS (if a resolver is enabled in the container)
        9100 # node-exporter
      ];
      allowedUDPPorts = [
        53 # DNS (if a resolver is enabled in the container)
      ];
    };
  };

  containers.media-mgmt = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.3";
    localAddress = "10.0.50.4";
    config = {
      imports = [
        ../nix.nix
        ../services/monitoring/agent/node-exporter-container.nix
        ../services/media/management/server
      ];

      networking = {
        hostName = "media-mgmt";
        enableIPv6 = false;
        defaultGateway = "10.0.50.3";
        nameservers = [ config.vars.lanIp ];
        useHostResolvConf = false;
        firewall.logRefusedConnections = true;
        firewall.logRefusedPackets = true;
        firewall.logRefusedUnicastsOnly = true;
      };
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/data" = {
        hostPath = "/srv/media";
        isReadOnly = false;
      };
      "/var/lib/radarr" = {
        hostPath = "/srv/appdata/media-mgmt/radarr";
        isReadOnly = false;
      };
      "/var/lib/sonarr" = {
        hostPath = "/srv/appdata/media-mgmt/sonarr";
        isReadOnly = false;
      };
      "/var/lib/prowlarr" = {
        hostPath = "/srv/appdata/media-mgmt/prowlarr";
        isReadOnly = false;
      };
      "/var/lib/sabnzbd" = {
        hostPath = "/srv/appdata/media-mgmt/sabnzbd";
        isReadOnly = false;
      };
      "/var/lib/bazarr" = {
        hostPath = "/srv/appdata/media-mgmt/bazarr";
        isReadOnly = false;
      };
      "/var/lib/recyclarr" = {
        hostPath = "/srv/appdata/media-mgmt/recyclarr";
        isReadOnly = false;
      };
      "/var/lib/lidarr" = {
        hostPath = "/srv/appdata/media-mgmt/lidarr";
        isReadOnly = false;
      };
      "/var/lib/jellyseerr" = {
        hostPath = "/srv/appdata/media-mgmt/jellyseerr";
        isReadOnly = false;
      };
      "/run/secrets/media.radarr.env" = {
        hostPath = "/run/secrets/media.radarr.env";
        isReadOnly = true;
      };
      "/run/secrets/media.sonarr.env" = {
        hostPath = "/run/secrets/media.sonarr.env";
        isReadOnly = true;
      };
      "/run/secrets/media.prowlarr.env" = {
        hostPath = "/run/secrets/media.prowlarr.env";
        isReadOnly = true;
      };
      "/run/secrets/media.sabnzbd.env" = {
        hostPath = "/run/secrets/media.sabnzbd.env";
        isReadOnly = true;
      };
      "/run/secrets/media.bazarr.env" = {
        hostPath = "/run/secrets/media.bazarr.env";
        isReadOnly = true;
      };
      "/run/secrets/media.recyclarr.radarr_api_key" = {
        hostPath = "/run/secrets/media.recyclarr.radarr_api_key";
        isReadOnly = true;
      };
      "/run/secrets/media.recyclarr.sonarr_api_key" = {
        hostPath = "/run/secrets/media.recyclarr.sonarr_api_key";
        isReadOnly = true;
      };
      "/run/secrets/media.lidarr.env" = {
        hostPath = "/run/secrets/media.lidarr.env";
        isReadOnly = true;
      };
      "/run/secrets/media.jellyseerr.env" = {
        hostPath = "/run/secrets/media.jellyseerr.env";
        isReadOnly = true;
      };
    };
  };
}
