{
  flake.nixosModules.containers-media-mgmt-lidarr = { config, lib, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    sops.secrets."media.lidarr.api_key" = { };
  
    sops.templates."media.lidarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "LIDARR__API_KEY=${config.sops.placeholder."media.lidarr.api_key"}";
    };
  
    virtualisation.quadlet.containers.lidarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/lidarr:3.1.0.4875-ls39";
        publishPorts = [ "127.0.0.1:8686:8686" ];
        networks = [ network.ref ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.lidarr.env".path ];
        volumes = [
          "/srv/appdata/media-mgmt/lidarr:/config"
          "/srv/media:/data"
        ];
      } // flakeLib.quadlet.mkHealthCheck { port = 8686; };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };
  
    environment.etc."alloy/lidarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "lidarr";
      hostName = config.networking.hostName;
    };
  
    services.nginx.virtualHosts."lidarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:8686";
    };
  };
}
