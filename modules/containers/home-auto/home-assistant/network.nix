{
  flake.nixosModules.containers-home-auto-home-assistant-network = { config, ... }:
  {
    virtualisation.quadlet.networks.home-auto = {
      networkConfig.interfaceName = "br-home-auto";
      networkConfig.ipv6 = false;
      networkConfig.subnets = [ config.vars.network.podmanSubnets.homeAuto ];
    };
  
    # macvlan network for LAN discovery (SSDP, mDNS, Zeroconf)
    # No gateway — LAN-only, no internet via this path.
    virtualisation.quadlet.networks.home-auto-macvlan = {
      networkConfig = {
        driver = "macvlan";
        ipv6 = false;
        subnets = [ config.vars.network.lanCidr ];
        options = {
          parent = config.vars.network.lanIf;
          mode = "bridge";
        };
      };
    };
  
    networking.firewall.interfaces.br-home-auto.allowedUDPPorts = [ 53 ];
    networking.firewall.interfaces.br-home-auto.allowedTCPPorts = [ 443 1883 8095 8123 ];
  };
}
