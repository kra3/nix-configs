{
  flake.nixosModules.containers-media-mgmt-audiobookshelf = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.audiobookshelf;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-audiobookshelf ];

    virtualisation.quadlet.containers.audiobookshelf = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.audiobookshelf).
        networks = [ "${network.ref}:ip=${ip}" ];
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
      upstream = "http://${ip}:80";
      forwardAuth = true;
    };
  };
}
