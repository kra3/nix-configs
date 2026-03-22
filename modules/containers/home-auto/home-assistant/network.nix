{ config, ... }:
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
      subnets = [ "192.168.1.0/24" ];
      gateways = [ "192.168.1.1" ];
      options = {
        parent = config.vars.network.lanIf;
        mode = "bridge";
      };
    };
  };

  networking.firewall.interfaces.br-home-auto.allowedUDPPorts = [ 53 ];
}
