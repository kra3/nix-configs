{
  flake.nixosModules.containers-media-mgmt-bookshelf = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-bookshelf ];

    sops.secrets."media.bookshelf.api_key" = { };

    sops.templates."media.bookshelf.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "BOOKSHELF__API_KEY=${config.sops.placeholder."media.bookshelf.api_key"}";
    };

    virtualisation.quadlet.containers.bookshelf = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/bookshelf:/config"
          "/srv/media:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."bookshelf.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:8787";
    };
  };
}
