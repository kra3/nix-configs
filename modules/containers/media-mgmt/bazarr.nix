{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  sops.secrets."media.bazarr.api_key" = { };

  sops.templates."media.bazarr.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = "BAZARR__API_KEY=${config.sops.placeholder."media.bazarr.api_key"}";
  };

  virtualisation.quadlet.containers.bazarr = {
    containerConfig = {
      image = "lscr.io/linuxserver/bazarr:1.6.0-ls355";
      healthCmd = "wget -qO-  http://localhost:6767/ping";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "30s";
      publishPorts = [ "127.0.0.1:6767:6767" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."media.bazarr.env".path ];
      volumes = [
        "/srv/appdata/media-mgmt/bazarr:/config"
        "/srv/media:/data"
      ];
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/bazarr.alloy".text = ''
    loki.source.journal "bazarr" {
      matches = "_SYSTEMD_UNIT=bazarr.service"
      labels = {
        job = "bazarr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."bazarr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:6767";
      proxyWebsockets = true;
    };
  };
}
