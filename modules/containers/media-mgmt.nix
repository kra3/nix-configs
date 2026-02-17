{ config, lib, ... }:
let
  containerLib = import ../lib { inherit lib config; };
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  isContainer = config.vars.media.backend == "container";
  isArcaneMedia = config.vars.media.backend == "arcane";
  # Proxy host: container IP for NixOS container, localhost for arcane (port forwarding)
  proxyHost = if isContainer then "10.0.50.4" else "127.0.0.1";
in
{
  # Shared by both backends
  users.groups.media.gid = 2000;

  # Host storage for media (shared by both backends)
  systemd.tmpfiles.rules = [
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
    "d /srv/appdata/media-mgmt/radarr 2770 root media - -"
    "d /srv/appdata/media-mgmt/sonarr 2770 root media - -"
    "d /srv/appdata/media-mgmt/prowlarr 2770 root media - -"
    "d /srv/appdata/media-mgmt/sabnzbd 2770 root media - -"
    "d /srv/appdata/media-mgmt/bazarr 2770 root media - -"
    "d /srv/appdata/media-mgmt/recyclarr 2770 root media - -"
    "d /srv/appdata/media-mgmt/lidarr 2770 root media - -"
    "d /srv/appdata/media-mgmt/jellyseerr 2770 root media - -"
  ];

  # Nginx proxies (shared by both backends, different proxy target)
  services.nginx.virtualHosts = lib.mkIf (isContainer || isArcaneMedia) {
    "radarr.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:7878";
        proxyWebsockets = true;
      };
    };
    "sonarr.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:8989";
        proxyWebsockets = true;
      };
    };
    "prowlarr.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:9696";
        proxyWebsockets = true;
      };
    };
    "sabnzbd.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:8080";
        proxyWebsockets = true;
      };
    };
    "bazarr.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:6767";
        proxyWebsockets = true;
      };
    };
    "lidarr.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:8686";
        proxyWebsockets = true;
      };
    };
    "jellyseerr.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://${proxyHost}:5055";
        proxyWebsockets = true;
      };
    };
  };

  # Container-specific configuration
  sops.secrets = lib.mkIf isContainer {
    "media.radarr.api_key" = {};
    "media.sonarr.api_key" = {};
    "media.prowlarr.api_key" = {};
    "media.sabnzbd.api_key" = {};
    "media.sabnzbd.nzb_key" = {};
    "media.bazarr.api_key" = {};
    "media.lidarr.api_key" = {};
    "media.jellyseerr.api_key" = {};
  };

  sops.templates = lib.mkIf isContainer {
    "media.radarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}";
    };
    "media.sonarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "SONARR__API_KEY=${config.sops.placeholder."media.sonarr.api_key"}";
    };
    "media.prowlarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "PROWLARR__API_KEY=${config.sops.placeholder."media.prowlarr.api_key"}";
    };
    "media.sabnzbd.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = ''
        SABNZBD__API_KEY=${config.sops.placeholder."media.sabnzbd.api_key"}
        SABNZBD__NZB_KEY=${config.sops.placeholder."media.sabnzbd.nzb_key"}
      '';
    };
    "media.bazarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "BAZARR__API_KEY=${config.sops.placeholder."media.bazarr.api_key"}";
    };
    "media.lidarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "LIDARR__API_KEY=${config.sops.placeholder."media.lidarr.api_key"}";
    };
    "media.jellyseerr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "JELLYSEERR__API_KEY=${config.sops.placeholder."media.jellyseerr.api_key"}";
    };
    "media.recyclarr.radarr_api_key" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = config.sops.placeholder."media.radarr.api_key";
    };
    "media.recyclarr.sonarr_api_key" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = config.sops.placeholder."media.sonarr.api_key";
    };
  };

  networking.firewall.interfaces = lib.mkIf isContainer {
    ve-media-mgmt = {
      allowedTCPPorts = [ 53 9100 ];
      allowedUDPPorts = [ 53 ];
    };
  };

  containers.media-mgmt = lib.mkIf isContainer ({
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
      "/etc/localtime".hostPath = "/etc/localtime";
      "/data" = { hostPath = "/srv/media"; isReadOnly = false; };
      "/var/lib/radarr" = { hostPath = "/srv/appdata/media-mgmt/radarr"; isReadOnly = false; };
      "/var/lib/sonarr" = { hostPath = "/srv/appdata/media-mgmt/sonarr"; isReadOnly = false; };
      "/var/lib/prowlarr" = { hostPath = "/srv/appdata/media-mgmt/prowlarr"; isReadOnly = false; };
      "/var/lib/sabnzbd" = { hostPath = "/srv/appdata/media-mgmt/sabnzbd"; isReadOnly = false; };
      "/var/lib/bazarr" = { hostPath = "/srv/appdata/media-mgmt/bazarr"; isReadOnly = false; };
      "/var/lib/recyclarr" = { hostPath = "/srv/appdata/media-mgmt/recyclarr"; isReadOnly = false; };
      "/var/lib/lidarr" = { hostPath = "/srv/appdata/media-mgmt/lidarr"; isReadOnly = false; };
      "/var/lib/jellyseerr" = { hostPath = "/srv/appdata/media-mgmt/jellyseerr"; isReadOnly = false; };
      "/run/secrets/media.radarr.env".hostPath = "/run/secrets/rendered/media.radarr.env";
      "/run/secrets/media.sonarr.env".hostPath = "/run/secrets/rendered/media.sonarr.env";
      "/run/secrets/media.prowlarr.env".hostPath = "/run/secrets/rendered/media.prowlarr.env";
      "/run/secrets/media.sabnzbd.env".hostPath = "/run/secrets/rendered/media.sabnzbd.env";
      "/run/secrets/media.bazarr.env".hostPath = "/run/secrets/rendered/media.bazarr.env";
      "/run/secrets/media.lidarr.env".hostPath = "/run/secrets/rendered/media.lidarr.env";
      "/run/secrets/media.jellyseerr.env".hostPath = "/run/secrets/rendered/media.jellyseerr.env";
      "/run/secrets/media.recyclarr.radarr_api_key".hostPath = "/run/secrets/rendered/media.recyclarr.radarr_api_key";
      "/run/secrets/media.recyclarr.sonarr_api_key".hostPath = "/run/secrets/rendered/media.recyclarr.sonarr_api_key";
    };
  });

  systemd.services."container@media-mgmt" = lib.mkIf isContainer (
    containerLib.container.definition.mkContainerSystemdDeps [ ]);
}
