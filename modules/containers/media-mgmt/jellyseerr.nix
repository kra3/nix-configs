{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.jellyseerr.api_key" = {};

  sops.templates."media.jellyseerr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "JELLYSEERR__API_KEY=${config.sops.placeholder."media.jellyseerr.api_key"}";
  };

  virtualisation.quadlet.containers.jellyseerr = {
    containerConfig = {
      image = "fallenbagel/jellyseerr:2.7.3";
      publishPorts = [ "127.0.0.1:5055:5055" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.jellyseerr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/jellyseerr:/app/config"
      ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/jellyseerr.alloy".text = ''
    loki.source.journal "jellyseerr" {
      matches = "_SYSTEMD_UNIT=jellyseerr.service"
      labels = {
        job = "jellyseerr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."jellyseerr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5055";
      proxyWebsockets = true;
    };
  };
}
