{
  flake.nixosModules.containers-media-mgmt-lidarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-lidarr ];

    sops.secrets."media.lidarr.api_key" = { };

    sops.templates."media.lidarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "LIDARR__API_KEY=${config.sops.placeholder."media.lidarr.api_key"}";
    };

    virtualisation.quadlet.containers.lidarr = {
      containerConfig = {
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/lidarr:/config"
          "/srv/media:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."lidarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:8686";
    };
  };
}
