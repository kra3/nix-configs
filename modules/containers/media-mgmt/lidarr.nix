{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.lidarr.api_key" = {};

  sops.templates."media.lidarr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "LIDARR__API_KEY=${config.sops.placeholder."media.lidarr.api_key"}";
  };

  virtualisation.quadlet.containers.lidarr = {
    containerConfig = {
      image = "lscr.io/linuxserver/lidarr:3.1.0.4875-ls29";
      healthCmd = "wget -qO-  http://localhost:8686/ping";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "30s";
      publishPorts = [ "127.0.0.1:8686:8686" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.lidarr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/lidarr:/config"
        "/srv/media:/data"
      ];
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/lidarr.alloy".text = ''
    loki.source.journal "lidarr" {
      matches = "_SYSTEMD_UNIT=lidarr.service"
      labels = {
        job = "lidarr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."lidarr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8686";
      proxyWebsockets = true;
    };
  };
}
