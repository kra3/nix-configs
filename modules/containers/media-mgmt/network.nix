{ ... }:
{
  virtualisation.quadlet.networks.media-mgmt = {
    networkConfig.interfaceName = "br-media-mgmt";
    networkConfig.ipv6 = false;
  };

  networking.firewall.interfaces.br-media-mgmt.allowedUDPPorts = [ 53 ];
}
