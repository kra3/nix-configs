{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.life;
in
{
  virtualisation.quadlet.containers.actualbudget = {
    containerConfig = {
      image = "actualbudget/actual-server:26.3.0";
      publishPorts = [ "127.0.0.1:5006:5006" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        TZ = "UTC";
        ACTUAL_HOSTNAME = "0.0.0.0";
      };
      volumes = [
        "/srv/appdata/life/actualbudget:/data"
      ];
    };
    unitConfig = {
      After = [ "life-network.service" ];
      Requires = [ "life-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/actualbudget.alloy".text = ''
    loki.source.journal "actualbudget" {
      matches = "_SYSTEMD_UNIT=actualbudget.service"
      labels = {
        job = "actualbudget",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."actualbudget.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5006";
      proxyWebsockets = true;
    };
  };
}
