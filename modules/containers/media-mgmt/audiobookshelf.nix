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
        # OIDC login calls auth.${domain} directly; route via the bridge
        # gateway since the LAN/public IP doesn't route back in from here.
        addHosts = [
          "auth.${config.vars.acme.domain}:10.3.1.1"
        ];
        volumes = [
          "/srv/appdata/media-mgmt/audiobookshelf/config:/config"
          "/srv/appdata/media-mgmt/audiobookshelf/metadata:/metadata"
          "/srv/media/library/books:/books"
          "/srv/media/library/audiobooks:/audiobooks"
          "/srv/media/bkup/Books/Ebooks:/ebooks:ro"
          "/srv/media/bkup/Books/Computer\ Science:/ebbok-compsec:ro"
        ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "896m";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    sops.secrets."media.audiobookshelf.oidc_client_secret" = { };

    # No forwardAuth: its auth_request redirect broke Audiobookshelf's own
    # AJAX admin calls (CORS on the cross-origin redirect). Native OIDC instead.
    services.nginx.virtualHosts."audiobookshelf.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      # Container's actual listen port (80), not the old published host
      # port (13378) — those only matched by coincidence of the publish
      # mapping, which no longer exists.
      upstream = "http://${ip}:80";
    };
  };
}
