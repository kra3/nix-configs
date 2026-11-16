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

      # Mounted by aiostreams/aiometadata: podman's own resolver would hide their IPs from AdGuard's aio-apps client rule.
      environment.etc."aio-resolv.conf".text = ''
        nameserver ${config.vars.network.lanIp}
      '';

      networking.firewall.interfaces.br-media-mgmt = {
        # TCP 53 is for those two containers' truncated-reply retries.
        allowedUDPPorts = [ 53 ];
        # Audiobookshelf/Seerr call auth.${domain} directly (own OIDC login).
        allowedTCPPorts = [
          53
          443
        ];
      };
    };
}
