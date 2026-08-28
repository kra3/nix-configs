{
  flake.nixosModules.containers-media-mgmt-bazarr = { config, lib, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    sops.secrets."media.bazarr.api_key" = { };
  
    sops.templates."media.bazarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "BAZARR__API_KEY=${config.sops.placeholder."media.bazarr.api_key"}";
    };
  
    virtualisation.quadlet.containers.bazarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/bazarr:v1.6.0-ls361";
        publishPorts = [ "127.0.0.1:6767:6767" ];
        networks = [ network.ref ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.bazarr.env".path ];
        volumes = [
          "/srv/appdata/media-mgmt/bazarr:/config"
          "/srv/media:/data"
        ];
      } // flakeLib.quadlet.mkHealthCheck { port = 6767; };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };
  
    environment.etc."alloy/bazarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "bazarr";
      hostName = config.networking.hostName;
    };
  
    services.nginx.virtualHosts."bazarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:6767";
    };
  };
}
