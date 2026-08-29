{
  flake.nixosModules.containers-media-mgmt-maintainerr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-maintainerr ];

    virtualisation.quadlet.containers.maintainerr = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/maintainerr:/opt/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."maintainerr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:6246";
      locationExtraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
      '';
    };
  };
}
