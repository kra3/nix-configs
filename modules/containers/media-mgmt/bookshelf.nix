{ config, lib, flakeLib, ... }:
let
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.bookshelf.api_key" = { };

  sops.templates."media.bookshelf.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "BOOKSHELF__API_KEY=${config.sops.placeholder."media.bookshelf.api_key"}";
  };

  virtualisation.quadlet.containers.bookshelf = {
    containerConfig = {
      image = "ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.20.129";
      publishPorts = [ "127.0.0.1:8787:8787" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.bookshelf.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/bookshelf:/config"
        "/srv/media:/data"
      ];
    } // flakeLib.quadlet.mkHealthCheck { port = 8787; };
  } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

  environment.etc."alloy/bookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
    name = "bookshelf";
    hostName = config.networking.hostName;
  };

  services.nginx.virtualHosts."bookshelf.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://127.0.0.1:8787";
  };
}
