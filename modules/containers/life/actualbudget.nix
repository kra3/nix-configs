{
  flake.nixosModules.containers-life-actualbudget = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.life;
  in
  {
    imports = [ flakeModules.nixos.services-finance-actualbudget ];

    virtualisation.quadlet.containers.actualbudget = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why.
        networks = [ "${network.ref}:ip=10.3.0.2" ];
        volumes = [
          "/srv/appdata/life/actualbudget:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "life-network.service" ]; };

    services.nginx.virtualHosts."actualbudget.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://10.3.0.2:5006";
      forwardAuth = true;
    };
  };
}
