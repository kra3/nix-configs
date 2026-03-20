{ ... }:
{
  virtualisation.quadlet.networks.media-mgmt = {
    networkConfig.interfaceName = "br-media-mgmt";
    networkConfig.ipv6 = false;
    networkConfig.subnets = [ "10.89.1.0/24" ];
  };

  networking.firewall.interfaces.br-media-mgmt.allowedUDPPorts = [ 53 ];
}
