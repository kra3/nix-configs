{
  flake.nixosModules.containers-media-mgmt-audiobookshelf = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-audiobookshelf ];

    virtualisation.quadlet.containers.audiobookshelf = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why.
        networks = [ "${network.ref}:ip=10.3.1.2" ];
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
      # Container's actual listen port (80), not the old published host
      # port (13378) — those only matched by coincidence of the publish
      # mapping, which no longer exists.
      upstream = "http://10.3.1.2:80";
      forwardAuth = true;
    };
  };
}
