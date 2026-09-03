{
  flake.nixosModules.containers-media-mgmt-bookshelf = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.bookshelf;
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
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.bookshelf).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [
          "/srv/appdata/media-mgmt/bookshelf:/config"
          "/srv/media:/data"
        ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "512Mi";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."bookshelf.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:8787";
      forwardAuth = true;
    };
  };
}
