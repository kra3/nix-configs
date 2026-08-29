{
  flake.nixosModules.containers-life-actualbudget = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.life;
  in
  {
    imports = [ flakeModules.nixos.services-finance-actualbudget ];

    virtualisation.quadlet.containers.actualbudget = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/life/actualbudget:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "life-network.service" ]; };

    services.nginx.virtualHosts."actualbudget.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:5006";
    };
  };
}
