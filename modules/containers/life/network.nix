{ ... }:
{
  virtualisation.quadlet.networks.life = {
    networkConfig.interfaceName = "br-life";
    networkConfig.ipv6 = false;
  };

  networking.firewall.interfaces.br-life.allowedUDPPorts = [ 53 ];
}
