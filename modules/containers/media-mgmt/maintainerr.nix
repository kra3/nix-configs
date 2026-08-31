{
  flake.nixosModules.containers-media-mgmt-maintainerr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.maintainerr;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-maintainerr ];

    virtualisation.quadlet.containers.maintainerr = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.maintainerr).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [
          "/srv/appdata/media-mgmt/maintainerr:/opt/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."maintainerr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:6246";
      forwardAuth = true;
      locationExtraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
      '';
    };
  };
}
