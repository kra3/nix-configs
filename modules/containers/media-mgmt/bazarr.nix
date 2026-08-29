{
  flake.nixosModules.containers-media-mgmt-bazarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-bazarr ];

    sops.secrets."media.bazarr.api_key" = { };

    sops.templates."media.bazarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "BAZARR__API_KEY=${config.sops.placeholder."media.bazarr.api_key"}";
    };

    virtualisation.quadlet.containers.bazarr = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/bazarr:/config"
          "/srv/media:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."bazarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:6767";
    };
  };
}
