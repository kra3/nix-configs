{
  flake.nixosModules.containers-media-mgmt-bazarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.bazarr;
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
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.bazarr).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [
          "/srv/appdata/media-mgmt/bazarr:/config"
          "/srv/media:/data"
        ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "512m";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."bazarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:6767";
      forwardAuth = true;
    };
  };
}
