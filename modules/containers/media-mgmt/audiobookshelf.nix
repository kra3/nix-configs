{ config, lib, flakeLib, ... }:
let
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  virtualisation.quadlet.containers.audiobookshelf = {
    containerConfig = {
      image = "ghcr.io/advplyr/audiobookshelf:2.36.0";
      publishPorts = [ "127.0.0.1:13378:80" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        TZ = "UTC";
      };
      volumes = [
        "/srv/appdata/media-mgmt/audiobookshelf/config:/config"
        "/srv/appdata/media-mgmt/audiobookshelf/metadata:/metadata"
        "/srv/media/library/books:/books"
        "/srv/media/library/audiobooks:/audiobooks"
        "/srv/media/bkup/Books/Ebooks:/ebooks:ro"
        "/srv/media/bkup/Books/Computer\ Science:/ebbok-compsec:ro"
      ];
    } // flakeLib.quadlet.mkHealthCheck { port = 80; path = "healthcheck"; };
  } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

  environment.etc."alloy/audiobookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
    name = "audiobookshelf";
    hostName = config.networking.hostName;
  };

  services.nginx.virtualHosts."audiobookshelf.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://127.0.0.1:13378";
  };
}
