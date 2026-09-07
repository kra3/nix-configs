{
  flake.nixosModules.services-tailscale =
    {
      config,
      lib,
      flakeLib,
      ...
    }:
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

      # Real storage; remapped onto the hardcoded --state=/var/lib/tailscale/... via BindPaths below.
      systemd.tmpfiles.rules = [
        "d /srv/appdata/tailscale 0700 root root - -"
      ];

      systemd.services.tailscaled.serviceConfig = lib.mkMerge [
        {
          BindPaths = [ "/srv/appdata/tailscale:/var/lib/tailscale" ];
        }
        (flakeLib.deployment-hardening.mkServiceSandbox {
          readWritePaths = [
            "/var/lib/tailscale"
            "/run/tailscale"
            "/run/resolvconf" # tailscaled clears its resolvconf entry on start/stop regardless of --accept-dns
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
    };
}
