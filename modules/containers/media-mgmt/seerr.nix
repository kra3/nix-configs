{ config, lib, flakeLib, ... }:
let
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.seerr.api_key" = { };

  sops.templates."media.seerr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "SEERR__API_KEY=${config.sops.placeholder."media.seerr.api_key"}";
  };

  virtualisation.quadlet.containers.seerr = {
    containerConfig = {
      image = "ghcr.io/seerr-team/seerr:v3.4.1";
      publishPorts = [ "127.0.0.1:5055:5055" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.seerr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/seerr:/app/config"
      ];
    }
    // flakeLib.quadlet.mkHealthCheck {
      port = 5055;
      path = "api/v1/status";
      startPeriod = "60s";
    };
  } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

  environment.etc."alloy/seerr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
    name = "seerr";
    hostName = config.networking.hostName;
  };

  services.nginx.virtualHosts."seerr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://127.0.0.1:5055";
  };
}
