{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.seerr.api_key" = {};

  sops.templates."media.seerr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "SEERR__API_KEY=${config.sops.placeholder."media.seerr.api_key"}";
  };

  virtualisation.quadlet.containers.seerr = {
    containerConfig = {
      image = "ghcr.io/seerr-team/seerr:v3.1.0";
      healthCmd = "wget -qO- http://localhost:5055/api/v1/status";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "60s";
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
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/seerr.alloy".text = ''
    loki.source.journal "seerr" {
      matches = "_SYSTEMD_UNIT=seerr.service"
      labels = {
        job = "seerr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."seerr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5055";
      proxyWebsockets = true;
    };
  };
}
