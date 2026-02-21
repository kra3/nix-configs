{ config, inputs, pkgs, lib, ... }:
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

  # Host storage for media-play container
  systemd.tmpfiles.rules = lib.mkMerge [
    [
      "d /srv/appdata/media-play 2770 root media - -"
    ]
    (lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) [
      "d /srv/appdata/media-play/jellyfin 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-play.config.services.navidrome.enable or false) [
      "d /srv/appdata/media-play/navidrome 2770 root media - -"
    ])
    (lib.mkIf (config.containers.media-play.config.services.music-assistant.enable or false) [
      "d /srv/appdata/media-play/music-assistant 2770 root media - -"
    ])
  ];

  # Host nginx reverse proxies for media-play container
  services.nginx.virtualHosts."jellyfin.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.6:8096";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."navidrome.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.navidrome.enable or false) {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.6:4533";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."mass.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.music-assistant.enable or false) {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.6:8095";
      proxyWebsockets = true;
    };
  };

  # Host firewall for media-play container
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
      domain = config.vars.acme.domain;
    };
  } // containerLib.container.definition.mkContainerNetwork {
    hostAddress = "10.0.50.5";
    localAddress = "10.0.50.6";
  } // {
    config = {
      imports = [
        ../services/system/nix.nix
        ../containers/common.nix
        inputs.declarative-jellyfin.nixosModules.default
        ../services/media/players
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
  users.groups.jellyfin = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    gid = 999;
  };

  sops.secrets."media.jellyfin.users.kra3.password" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    mode = "0440";
    group = "jellyfin";
  };
  sops.secrets."media.jellyfin.users.home.password" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    mode = "0440";
    group = "jellyfin";
  };
  sops.secrets."media.jellyfin.apikeys.jellyseerr" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    mode = "0440";
    group = "jellyfin";
  };
}
