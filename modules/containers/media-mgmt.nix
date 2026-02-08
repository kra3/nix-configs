{ config, lib, ... }:
let
  containerLib = import ../lib { inherit lib config; };
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
in
{
  # Host group for media files
  users.groups.media = {
    gid = 2000;
  };

  # Host storage for media-mgmt container
  systemd.tmpfiles.rules = lib.mkMerge [
    [
      "d /srv/media 2775 root media - -"
      "d /srv/media/downloads 2775 root media - -"
      "d /srv/media/downloads/usenet 2775 root media - -"
      "d /srv/media/downloads/usenet/incomplete 2775 root media - -"
      "d /srv/media/downloads/usenet/complete 2775 root media - -"
      "d /srv/media/downloads/usenet/complete/tv 2775 root media - -"
      "d /srv/media/downloads/usenet/complete/movies 2775 root media - -"
      "d /srv/media/downloads/usenet/complete/music 2775 root media - -"
      "d /srv/media/downloads/usenet/complete/books 2775 root media - -"
      "d /srv/media/downloads/torrent 2775 root media - -"
      "d /srv/media/downloads/torrent/incomplete 2775 root media - -"
      "d /srv/media/downloads/torrent/complete 2775 root media - -"
      "d /srv/media/library 2775 root media - -"
      "d /srv/media/library/movies 2775 root media - -"
      "d /srv/media/library/tv 2775 root media - -"
      "d /srv/media/library/music 2775 root media - -"
      "d /srv/media/library/books 2775 root media - -"
      "d /srv/media/library/anime 2775 root media - -"
      "d /srv/media/library/anime/movies 2775 root media - -"
      "d /srv/media/library/anime/tv 2775 root media - -"
      "d /srv/media/library/audiobooks 2775 root media - -"
      "d /srv/media/library/homevideos 2775 root media - -"
      "d /srv/appdata 2770 root media - -"
      "d /srv/appdata/media-mgmt 2770 root media - -"
    ]
    (lib.mkIf (config.containers.media-mgmt.config.services.radarr.enable or false) [
      "d /srv/appdata/media-mgmt/radarr 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.sonarr.enable or false) [
      "d /srv/appdata/media-mgmt/sonarr 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.prowlarr.enable or false) [
      "d /srv/appdata/media-mgmt/prowlarr 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.sabnzbd.enable or false) [
      "d /srv/appdata/media-mgmt/sabnzbd 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.bazarr.enable or false) [
      "d /srv/appdata/media-mgmt/bazarr 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.recyclarr.enable or false) [
      "d /srv/appdata/media-mgmt/recyclarr 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.lidarr.enable or false) [
      "d /srv/appdata/media-mgmt/lidarr 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-mgmt.config.services.jellyseerr.enable or false) [
      "d /srv/appdata/media-mgmt/jellyseerr 2770 root media - -"
    ])
  ];

  # Host nginx reverse proxies for media-mgmt container
  services.nginx.virtualHosts."radarr.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.radarr.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:7878";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."sonarr.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.sonarr.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:8989";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."prowlarr.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.prowlarr.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:9696";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."sabnzbd.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.sabnzbd.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:8080";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."bazarr.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.bazarr.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:6767";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."lidarr.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.lidarr.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:8686";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."jellyseerr.karunagath.in" = lib.mkIf (config.containers.media-mgmt.config.services.jellyseerr.enable or false) {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.4:5055";
      proxyWebsockets = true;
    };
  };

  # Host secrets for media-mgmt container
  sops.secrets."media.radarr.env" = lib.mkIf (config.containers.media-mgmt.config.services.radarr.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };
  sops.secrets."media.sonarr.env" = lib.mkIf (config.containers.media-mgmt.config.services.sonarr.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };
  sops.secrets."media.prowlarr.env" = lib.mkIf (config.containers.media-mgmt.config.services.prowlarr.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };
  sops.secrets."media.sabnzbd.env" = lib.mkIf (config.containers.media-mgmt.config.services.sabnzbd.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };
  sops.secrets."media.bazarr.env" = lib.mkIf (config.containers.media-mgmt.config.services.bazarr.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };
  sops.secrets."media.recyclarr.radarr_api_key" = lib.mkIf (config.containers.media-mgmt.config.services.recyclarr.enable or false) {
    owner = "root";
    group = "root";
    mode = "0400";
  };
  sops.secrets."media.recyclarr.sonarr_api_key" = lib.mkIf (config.containers.media-mgmt.config.services.recyclarr.enable or false) {
    owner = "root";
    group = "root";
    mode = "0400";
  };
  sops.secrets."media.lidarr.env" = lib.mkIf (config.containers.media-mgmt.config.services.lidarr.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };
  sops.secrets."media.jellyseerr.env" = lib.mkIf (config.containers.media-mgmt.config.services.jellyseerr.enable or false) {
    owner = "root";
    group = "media";
    mode = "0440";
  };

  # Host firewall for media-mgmt container
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

  containers.media-mgmt = ({
    autoStart = true;
  } // containerLib.container.definition.mkContainerNetwork {
    hostAddress = "10.0.50.3";
    localAddress = "10.0.50.4";
  } // {
    config = {
      imports = [
        ../services/system/nix.nix
        ../containers/common.nix
        ../services/media/management
      ];

      networking = {
        hostName = "media-mgmt";
        defaultGateway = "10.0.50.3";
        nameservers = [ config.vars.network.lanIp ];
      };
    };
    bindMounts = {
      "/etc/localtime" = {
        hostPath = "/etc/localtime";
        isReadOnly = true;
      };
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
  });

  systemd.services."container@media-mgmt" =
    containerLib.container.definition.mkContainerSystemdDeps [ ];
}
