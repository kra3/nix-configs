{ config, lib, ... }:
let
  containerLib = import ../../lib { inherit lib; };
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.radarr.api_key" = { };

  sops.templates."media.radarr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}";
  };

  virtualisation.quadlet.containers.radarr = {
    containerConfig = {
      image = "lscr.io/linuxserver/radarr:6.3.0.10514-ls313";
      publishPorts = [ "127.0.0.1:7878:7878" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.radarr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/radarr:/config"
        "/srv/media:/data"
      ];
    } // containerLib.quadlet.mkHealthCheck { port = 7878; };
  } // containerLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

  environment.etc."alloy/radarr.alloy".text = containerLib.observability.mkAlloyJournalSource {
    name = "radarr";
    hostName = config.networking.hostName;
  };

  services.nginx.virtualHosts."radarr.${config.vars.acme.domain}" = containerLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://127.0.0.1:7878";
  };
}
