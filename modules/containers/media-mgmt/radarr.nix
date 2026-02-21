{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.radarr.api_key" = {};

  sops.templates."media.radarr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}";
  };

  virtualisation.quadlet.containers.radarr = {
    containerConfig = {
      image = "lscr.io/linuxserver/radarr:6.0.4";
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
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/radarr.alloy".text = ''
    loki.source.journal "radarr" {
      matches = "_SYSTEMD_UNIT=radarr.service"
      labels = {
        job = "radarr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."radarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:7878";
      proxyWebsockets = true;
    };
  };
}
