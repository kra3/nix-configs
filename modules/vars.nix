{
  flake.nixosModules.vars =
    # Global configuration variables
    #
    # This module defines shared configuration options used across all modules.
    # It lives at modules/vars.nix (not in a subdirectory) because it's a
    # cross-cutting concern referenced by:
    # - Host configuration (hosts/sutala/configuration.nix)
    # - All containers (modules/containers/*.nix)
    # - Services (modules/services/**)
    # - Infrastructure modules (modules/services/infrastructure/*)
    #
    # Keeping it at the module root ensures consistent relative paths from all consumers.
    { lib, ... }:
    {
      options.vars = {
        network = {
          lanIf = lib.mkOption {
            type = lib.types.str;
            default = "enp2s0";
            description = "LAN network interface";
          };
          lanIp = lib.mkOption {
            type = lib.types.str;
            default = "192.168.1.10";
            description = "LAN IP address";
          };
          lanCidr = lib.mkOption {
            type = lib.types.str;
            default = "192.168.1.0/24";
            description = "LAN subnet CIDR";
          };
          nginxAllowCidrs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "192.168.1.0/24"
              "100.64.0.0/10"
              "127.0.0.1"
              "10.3.0.0/16"
            ];
            description = "CIDR blocks allowed for nginx access";
          };
          podmanSubnets = {
            life = lib.mkOption {
              type = lib.types.str;
              default = "10.3.0.0/24";
              description = "Podman bridge subnet for life zone (br-life)";
            };
            mediaMgmt = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.0/24";
              description = "Podman bridge subnet for media-mgmt zone (br-media-mgmt)";
            };
            homeAuto = lib.mkOption {
              type = lib.types.str;
              default = "10.3.2.0/24";
              description = "Podman bridge subnet for iot zone (br-home-auto)";
            };
          };
          containers = {
            monitoring = {
              hostAddress = lib.mkOption {
                type = lib.types.str;
                default = "10.3.255.1";
                description = "Host-side veth address for monitoring container";
              };
              localAddress = lib.mkOption {
                type = lib.types.str;
                default = "10.3.255.2";
                description = "Container-side veth address for monitoring container";
              };
            };
            mediaPlay = {
              hostAddress = lib.mkOption {
                type = lib.types.str;
                default = "10.3.255.5";
                description = "Host-side veth address for media-play container";
              };
              localAddress = lib.mkOption {
                type = lib.types.str;
                default = "10.3.255.6";
                description = "Container-side veth address for media-play container";
              };
            };
            homeAuto = {
              hostAddress = lib.mkOption {
                type = lib.types.str;
                default = "10.3.255.9";
                description = "Host-side veth address for home-auto container";
              };
              localAddress = lib.mkOption {
                type = lib.types.str;
                default = "10.3.255.10";
                description = "Container-side veth address for home-auto container";
              };
            };
          };
          # Pinned br-media-mgmt/br-life bridge IPs for apps wired to Authelia
          # forward-auth: nginx routes to these directly instead of via a
          # 127.0.0.1 publish (see media-mgmt/radarr.nix), so the address has
          # to be stable across deploys rather than left to podman's dynamic
          # allocation. Centralized here so it's set once, not duplicated
          # between each app's `networks` and its nginx `upstream`.
          podmanAddresses = {
            radarr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.13";
              description = "Pinned br-media-mgmt IP for radarr";
            };
            bazarr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.3";
              description = "Pinned br-media-mgmt IP for bazarr";
            };
            sonarr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.10";
              description = "Pinned br-media-mgmt IP for sonarr";
            };
            prowlarr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.14";
              description = "Pinned br-media-mgmt IP for prowlarr";
            };
            lidarr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.15";
              description = "Pinned br-media-mgmt IP for lidarr";
            };
            sabnzbd = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.12";
              description = "Pinned br-media-mgmt IP for sabnzbd";
            };
            maintainerr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.8";
              description = "Pinned br-media-mgmt IP for maintainerr";
            };
            aiostreams = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.50";
              # .16 collided with an existing dynamic lease; .50 clears that range.
              description = "Pinned br-media-mgmt IP for aiostreams";
            };
            seerr = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.11";
              description = "Pinned br-media-mgmt IP for seerr";
            };
            bookshelf = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.4";
              description = "Pinned br-media-mgmt IP for bookshelf";
            };
            audiobookshelf = lib.mkOption {
              type = lib.types.str;
              default = "10.3.1.2";
              description = "Pinned br-media-mgmt IP for audiobookshelf";
            };
            actualbudget = lib.mkOption {
              type = lib.types.str;
              default = "10.3.0.2";
              description = "Pinned br-life IP for actualbudget";
            };
            ghostfolio = lib.mkOption {
              type = lib.types.str;
              default = "10.3.0.4";
              description = "Pinned br-life IP for ghostfolio";
            };
          };
          # Centralized since consumers outside the pod's own file need the address too (e.g. surasa's snapclient).
          macvlanAddresses = {
            musicAssistant = lib.mkOption {
              type = lib.types.str;
              default = "192.168.1.36";
              description = "Pinned home-auto-macvlan IP for music-assistant";
            };
          };
        };
        acme = {
          email = lib.mkOption {
            type = lib.types.str;
            default = "the1.arun@gmail.com";
            description = "Email for ACME certificates";
          };
          domain = lib.mkOption {
            type = lib.types.str;
            default = "karunagath.in";
            description = "Primary domain for wildcard TLS certificate";
          };
        };
      };
    };
}
