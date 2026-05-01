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
}
