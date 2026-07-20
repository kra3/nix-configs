{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.prowlarr.api_key" = { };

  sops.templates."media.prowlarr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "PROWLARR__API_KEY=${config.sops.placeholder."media.prowlarr.api_key"}";
  };

  virtualisation.quadlet.containers.prowlarr = {
    containerConfig = {
      image = "lscr.io/linuxserver/prowlarr:2.4.0.5397-ls154";
      healthCmd = "wget -qO-  http://localhost:9696/ping";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "30s";
      publishPorts = [ "127.0.0.1:9696:9696" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.prowlarr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/prowlarr:/config"
      ];
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/prowlarr.alloy".text = ''
    loki.source.journal "prowlarr" {
      matches = "_SYSTEMD_UNIT=prowlarr.service"
      labels = {
        job = "prowlarr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."prowlarr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9696";
      proxyWebsockets = true;
    };
  };
}
