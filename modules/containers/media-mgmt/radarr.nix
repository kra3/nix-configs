{
  flake.nixosModules.containers-media-mgmt-radarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-radarr ];

    sops.secrets."media.radarr.api_key" = { };

    sops.templates."media.radarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}";
    };

    virtualisation.quadlet.containers.radarr = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/radarr:/config"
          "/srv/media:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."radarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:7878";
    };
  };
}
