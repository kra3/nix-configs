{
  flake.nixosModules.containers-media-mgmt-network = { config, ... }:
  {
    virtualisation.quadlet.networks.media-mgmt = {
      networkConfig.interfaceName = "br-media-mgmt";
      networkConfig.ipv6 = false;
      networkConfig.subnets = [ config.vars.network.podmanSubnets.mediaMgmt ];
    };
  
    networking.firewall.interfaces.br-media-mgmt.allowedUDPPorts = [ 53 ];
  };
}
