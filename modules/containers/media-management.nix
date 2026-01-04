{
  containers.media-management = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.3";
    localAddress = "10.0.50.4";
    config = {
      imports = [
        ../nix.nix
        ../services/media/management/server
      ];

      networking.hostName = "media-management";
      networking.enableIPv6 = false;
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/data" = {
        hostPath = "/srv/media";
        isReadOnly = false;
      };
      "/var/lib/radarr" = {
        hostPath = "/src/appdata/media-management/radarr";
        isReadOnly = false;
      };
      "/var/lib/sonarr" = {
        hostPath = "/src/appdata/media-management/sonarr";
        isReadOnly = false;
      };
      "/var/lib/prowlarr" = {
        hostPath = "/src/appdata/media-management/prowlarr";
        isReadOnly = false;
      };
      "/var/lib/sabnzbd" = {
        hostPath = "/src/appdata/media-management/sabnzbd";
        isReadOnly = false;
      };
      "/var/lib/bazarr" = {
        hostPath = "/src/appdata/media-management/bazarr";
        isReadOnly = false;
      };
      "/var/lib/recyclarr" = {
        hostPath = "/src/appdata/media-management/recyclarr";
        isReadOnly = false;
      };
      "/var/lib/lidarr" = {
        hostPath = "/src/appdata/media-management/lidarr";
        isReadOnly = false;
      };
      "/var/lib/jellyseerr" = {
        hostPath = "/src/appdata/media-management/jellyseerr";
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
      "/run/secrets/media.recyclarr.env" = {
        hostPath = "/run/secrets/media.recyclarr.env";
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
