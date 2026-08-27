{ config, inputs, pkgs, lib, ... }:
let
  containerLib = import ../lib { inherit lib; };
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
  ];

  # Host nginx reverse proxies for media-play container
  services.nginx.virtualHosts."jellyfin.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${config.vars.network.containers.mediaPlay.localAddress}:8096";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."navidrome.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.navidrome.enable or false) {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${config.vars.network.containers.mediaPlay.localAddress}:4533";
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
      monitoringLocalAddress = config.vars.network.containers.monitoring.localAddress;
    };
  } // containerLib.container.definition.mkContainerNetwork {
    hostAddress = config.vars.network.containers.mediaPlay.hostAddress;
    localAddress = config.vars.network.containers.mediaPlay.localAddress;
  } // {
    config = {
      imports = [
        ../services/system/nix-defaults-nixos.nix
        ../containers/common.nix
        inputs.declarative-jellyfin.nixosModules.default
        ../services/media/players
      ];

      nixpkgs.overlays = [
        inputs.self.overlays.default
      ];

      # Containers re-evaluate their own nixpkgs.config and don't inherit the
      # host's (only nixpkgs.hostPlatform is inherited) -- this must be
      # restated here, not just in modules/hardware/intel-igpu.nix, or
      # hardware.graphics.extraPackages below fails to evaluate.
      nixpkgs.config.permittedInsecurePackages = [
        "intel-media-sdk-23.2.2"
      ];

      networking = {
        hostName = "media-play";
        defaultGateway = config.vars.network.containers.mediaPlay.hostAddress;
        nameservers = [ config.vars.network.lanIp ];
        firewall.allowedTCPPorts = [
          4533 # Navidrome
          8096 # Jellyfin
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

      "/run/secrets/media.jellyfin.users.kra3.password" = {
        hostPath = "/run/secrets/media.jellyfin.users.kra3.password";
        isReadOnly = true;
      };
      "/run/secrets/media.jellyfin.users.home.password" = {
        hostPath = "/run/secrets/media.jellyfin.users.home.password";
        isReadOnly = true;
      };
      "/run/secrets/media.jellyfin.apikeys.seerr" = {
        hostPath = "/run/secrets/media.jellyfin.apikeys.seerr";
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
  sops.secrets."media.jellyfin.apikeys.seerr" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
    mode = "0440";
    group = "jellyfin";
  };
}
