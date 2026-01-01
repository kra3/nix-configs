{
  services.technitium-dns-server = {
    enable = true;
    openFirewall = false;
  };

  networking.firewall.interfaces.enp2s0.allowedTCPPorts = [
    53
    5380
  ];
  networking.firewall.interfaces.enp2s0.allowedUDPPorts = [ 53 ];
}
