{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.media-mgmt;
in
{
  virtualisation.quadlet.containers.maintainerr = {
    containerConfig = {
      image = "ghcr.io/maintainerr/maintainerr:3.8.0";
      healthCmd = "wget -qO- http://localhost:6246/healthcheck";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "60s";
      publishPorts = [ "127.0.0.1:6246:6246" ];
      networks = [ network.ref ];
      logDriver = "journald";
      user = "1000:2000";
      environments = {
        PUID = "1000";
        PGID = "2000";
        TZ = "UTC";
      };
      volumes = [
        "/srv/appdata/media-mgmt/maintainerr:/opt/data"
      ];
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/maintainerr.alloy".text = ''
    loki.source.journal "maintainerr" {
      matches = "_SYSTEMD_UNIT=maintainerr.service"
      labels = {
        job = "maintainerr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."maintainerr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:6246";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
      '';
    };
  };
}
