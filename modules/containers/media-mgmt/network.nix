{
  flake.nixosModules.containers-media-mgmt-network =
    { config, ... }:
    {
      virtualisation.quadlet.networks.media-mgmt = {
        networkConfig.interfaceName = "br-media-mgmt";
        networkConfig.ipv6 = false;
        networkConfig.subnets = [ config.vars.network.podmanSubnets.mediaMgmt ];
        # Keep dynamic allocation out of the low addresses pinned in vars.nix (podmanAddresses.*).
        networkConfig.ipRanges = [ "10.3.1.128/25" ];
      };

      networking.firewall.interfaces.br-media-mgmt = {
        allowedUDPPorts = [ 53 ];
        # Audiobookshelf/Seerr call auth.${domain} directly (own OIDC login).
        allowedTCPPorts = [ 443 ];
      };
    };
}
