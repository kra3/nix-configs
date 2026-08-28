{ config, lib, flakeLib, ... }:
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

  systemd.services.tailscaled.serviceConfig = lib.mkMerge [
    (flakeLib.deployment-hardening.mkServiceSandbox {
      readWritePaths = [
        "/var/lib/tailscale"
        "/run/tailscale"
      ];
      capabilities = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
      ];
      allowNetworkNamespaces = true;
      extraAddressFamilies = [ "AF_NETLINK" ];
    })
  ];

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      53
      443
    ];
    allowedUDPPorts = [ 53 ];
  };
}
