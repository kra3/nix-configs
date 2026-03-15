{ ... }:
{
  virtualisation.quadlet.networks.life = {
    networkConfig.interfaceName = "br-life";
    networkConfig.ipv6 = false;
    networkConfig.subnets = [ "10.89.0.0/24" ];
  };

  networking.firewall.interfaces.br-life.allowedUDPPorts = [ 53 ];
}
