{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.bookshelf.api_key" = {};

  sops.templates."media.bookshelf.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "BOOKSHELF__API_KEY=${config.sops.placeholder."media.bookshelf.api_key"}";
  };

  virtualisation.quadlet.containers.bookshelf = {
    containerConfig = {
      image = "ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.20.129";
      healthCmd = "wget -qO- http://localhost:8787/ping";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "30s";
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
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/bookshelf.alloy".text = ''
    loki.source.journal "bookshelf" {
      matches = "_SYSTEMD_UNIT=bookshelf.service"
      labels = {
        job = "bookshelf",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."bookshelf.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8787";
      proxyWebsockets = true;
    };
  };
}
