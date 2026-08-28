{
  flake.nixosModules.containers-media-mgmt-maintainerr = { config, lib, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    virtualisation.quadlet.containers.maintainerr = {
      containerConfig = {
        image = "ghcr.io/maintainerr/maintainerr:3.23.0";
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
      }
      // flakeLib.quadlet.mkHealthCheck {
        port = 6246;
        path = "healthcheck";
        startPeriod = "60s";
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };
  
    environment.etc."alloy/maintainerr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "maintainerr";
      hostName = config.networking.hostName;
    };
  
    services.nginx.virtualHosts."maintainerr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:6246";
      locationExtraConfig = ''
        proxy_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
      '';
    };
  };
}
