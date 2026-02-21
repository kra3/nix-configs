{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.sonarr.api_key" = {};

  sops.templates."media.sonarr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "SONARR__API_KEY=${config.sops.placeholder."media.sonarr.api_key"}";
  };

  virtualisation.quadlet.containers.sonarr = {
    containerConfig = {
      image = "lscr.io/linuxserver/sonarr:4.0.16";
      publishPorts = [ "127.0.0.1:8989:8989" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.sonarr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/sonarr:/config"
        "/srv/media:/data"
      ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/sonarr.alloy".text = ''
    loki.source.journal "sonarr" {
      matches = "_SYSTEMD_UNIT=sonarr.service"
      labels = {
        job = "sonarr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."sonarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8989";
      proxyWebsockets = true;
    };
  };
}
