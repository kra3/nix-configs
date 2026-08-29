{
  flake.nixosModules.containers-media-mgmt-seerr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-seerr ];

    sops.secrets."media.seerr.api_key" = { };

    sops.templates."media.seerr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "SEERR__API_KEY=${config.sops.placeholder."media.seerr.api_key"}";
    };

    virtualisation.quadlet.containers.seerr = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/seerr:/app/config"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."seerr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:5055";
    };
  };
}
