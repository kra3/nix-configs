{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.sabnzbd.api_key" = {};
  sops.secrets."media.sabnzbd.nzb_key" = {};

  sops.templates."media.sabnzbd.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = ''
      SABNZBD__API_KEY=${config.sops.placeholder."media.sabnzbd.api_key"}
      SABNZBD__NZB_KEY=${config.sops.placeholder."media.sabnzbd.nzb_key"}
    '';
  };

  virtualisation.quadlet.containers.sabnzbd = {
    containerConfig = {
      image = "lscr.io/linuxserver/sabnzbd:4.5.5-ls244";
      healthCmd = "wget -qO- http://localhost:8080/api?mode=version";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "60s";
      publishPorts = [ "127.0.0.1:8080:8080" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
        HAS_IPV6 = "false";
      };
      environmentFiles = [ config.sops.templates."media.sabnzbd.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/sabnzbd:/config"
        "/srv/media/downloads:/data/downloads"
      ];
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/sabnzbd.alloy".text = ''
    loki.source.journal "sabnzbd" {
      matches = "_SYSTEMD_UNIT=sabnzbd.service"
      labels = {
        job = "sabnzbd",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."sabnzbd.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
    };
  };
}
