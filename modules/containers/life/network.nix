{
  flake.nixosModules.containers-life-network =
    { config, ... }:
    {
      virtualisation.quadlet.networks.life = {
        networkConfig.interfaceName = "br-life";
        networkConfig.ipv6 = false;
        networkConfig.subnets = [ config.vars.network.podmanSubnets.life ];
      };

      networking.firewall.interfaces.br-life.allowedUDPPorts = [ 53 ];
      # Ghostfolio/Actual Budget call auth.${domain} directly (own OIDC login).
      networking.firewall.interfaces.br-life.allowedTCPPorts = [ 443 ];
    };
}
