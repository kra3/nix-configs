{
  flake.nixosModules.containers-media-mgmt-prowlarr = { config, lib, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    sops.secrets."media.prowlarr.api_key" = { };
  
    sops.templates."media.prowlarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "PROWLARR__API_KEY=${config.sops.placeholder."media.prowlarr.api_key"}";
    };
  
    virtualisation.quadlet.containers.prowlarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/prowlarr:2.5.2.5491-ls156";
        publishPorts = [ "127.0.0.1:9696:9696" ];
        networks = [ network.ref ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.prowlarr.env".path ];
        volumes = [
          "/srv/appdata/media-mgmt/prowlarr:/config"
        ];
      } // flakeLib.quadlet.mkHealthCheck { port = 9696; };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };
  
    environment.etc."alloy/prowlarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "prowlarr";
      hostName = config.networking.hostName;
    };
  
    services.nginx.virtualHosts."prowlarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:9696";
    };
  };
}
