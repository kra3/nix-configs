{ config, lib, ... }:
let
  containerLib = import ../../lib { inherit lib; };
  network = config.virtualisation.quadlet.networks.life;
in
{
  virtualisation.quadlet.containers.actualbudget = {
    containerConfig = {
      image = "actualbudget/actual-server:26.8.1";
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
  } // containerLib.quadlet.mkNetworkDeps { networkServices = [ "life-network.service" ]; };

  environment.etc."alloy/actualbudget.alloy".text = containerLib.observability.mkAlloyJournalSource {
    name = "actualbudget";
    hostName = config.networking.hostName;
  };

  services.nginx.virtualHosts."actualbudget.${config.vars.acme.domain}" = containerLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://127.0.0.1:5006";
  };
}
