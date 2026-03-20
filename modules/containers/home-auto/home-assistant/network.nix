{ ... }:
{
  virtualisation.quadlet.networks.home-auto = {
    networkConfig.interfaceName = "br-home-auto";
    networkConfig.ipv6 = false;
    networkConfig.subnets = [ "10.89.2.0/24" ];
  };

  networking.firewall.interfaces.br-home-auto.allowedUDPPorts = [ 53 ];
}
