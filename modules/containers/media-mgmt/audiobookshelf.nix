{
  flake.nixosModules.containers-media-mgmt-audiobookshelf = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-audiobookshelf ];

    virtualisation.quadlet.containers.audiobookshelf = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/audiobookshelf/config:/config"
          "/srv/appdata/media-mgmt/audiobookshelf/metadata:/metadata"
          "/srv/media/library/books:/books"
          "/srv/media/library/audiobooks:/audiobooks"
          "/srv/media/bkup/Books/Ebooks:/ebooks:ro"
          "/srv/media/bkup/Books/Computer\ Science:/ebbok-compsec:ro"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."audiobookshelf.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:13378";
    };
  };
}
