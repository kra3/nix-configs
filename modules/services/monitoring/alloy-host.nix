{
  flake.nixosModules.services-monitoring-alloy-host =
  { config, lib, flakeLib, ... }:
  {
    options.services.monitoringAlloyHost.lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.vars.network.containers.monitoring.localAddress}:3100/loki/api/v1/push";
      description = "Loki push endpoint for this host's Alloy agent -- override for hosts that can't reach the monitoring container's veth address directly (e.g. surasa, via the loki.<domain> nginx vhost).";
    };

    imports = [
      (flakeLib.observability.mkAlloyAgent {
        hostName = config.networking.hostName;
        lokiUrl = config.services.monitoringAlloyHost.lokiUrl;
        extraGroups =
          lib.optionals (config.services.nginx.enable or false) [ "nginx" ]
          ++ lib.optionals (config.services.adguardhome.enable or false) [ "adguardhome" ];
      })
    ];
  };
}
