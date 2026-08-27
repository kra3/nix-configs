{ config, lib, flakeLib, ... }:
let
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.sabnzbd.api_key" = { };
  sops.secrets."media.sabnzbd.nzb_key" = { };

  sops.templates."media.sabnzbd.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = ''
      SABNZBD__API_KEY=${config.sops.placeholder."media.sabnzbd.api_key"}
      SABNZBD__NZB_KEY=${config.sops.placeholder."media.sabnzbd.nzb_key"}
    '';
  };

  virtualisation.quadlet.containers.sabnzbd = {
    containerConfig = {
      image = "lscr.io/linuxserver/sabnzbd:5.1.1-ls267";
      publishPorts = [ "127.0.0.1:8080:8080" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
        HAS_IPV6 = "false";
      };
      environmentFiles = [ config.sops.templates."media.sabnzbd.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/sabnzbd:/config"
        "/srv/media/downloads:/data/downloads"
      ];
    }
    // flakeLib.quadlet.mkHealthCheck {
      port = 8080;
      path = "api?mode=version";
      startPeriod = "60s";
    };
  } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

  environment.etc."alloy/sabnzbd.alloy".text = flakeLib.observability.mkAlloyJournalSource {
    name = "sabnzbd";
    hostName = config.networking.hostName;
  };

  services.nginx.virtualHosts."sabnzbd.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://127.0.0.1:8080";
  };
}
