{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  virtualisation.quadlet.containers.audiobookshelf = {
    containerConfig = {
      image = "ghcr.io/advplyr/audiobookshelf:2.36.0";
      healthCmd = "wget -qO- http://localhost:80/healthcheck";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "30s";
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
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/audiobookshelf.alloy".text = ''
    loki.source.journal "audiobookshelf" {
      matches = "_SYSTEMD_UNIT=audiobookshelf.service"
      labels = {
        job = "audiobookshelf",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."audiobookshelf.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:13378";
      proxyWebsockets = true;
    };
  };
}
