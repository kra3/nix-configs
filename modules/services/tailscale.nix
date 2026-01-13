{ config, ... }:
{
  sops.secrets."tailscale.authkey" = { };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale.authkey".path;
    openFirewall = true;
    useRoutingFeatures = "both";
    extraUpFlags = [
      "--advertise-routes=192.168.1.10/32"
      "--advertise-exit-node"
      "--accept-dns=false"
    ];
    extraSetFlags = [
      "--advertise-routes=192.168.1.10/32"
      "--advertise-exit-node"
    ];
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      53
      443
    ];
    allowedUDPPorts = [ 53 ];
  };
}
