{
  flake.nixosModules.containers-life-actualbudget = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.life;
    ip = config.vars.network.podmanAddresses.actualbudget;
  in
  {
    imports = [ flakeModules.nixos.services-finance-actualbudget ];

    virtualisation.quadlet.containers.actualbudget = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.actualbudget).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [
          "/srv/appdata/life/actualbudget:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "life-network.service" ]; };

    services.nginx.virtualHosts."actualbudget.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:5006";
      forwardAuth = true;
    };
  };
}
