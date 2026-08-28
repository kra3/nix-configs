{
  flake.nixosModules.services-monitoring-alloy-host =
  { config, lib, flakeLib, ... }:
  {
    imports = [
      (flakeLib.observability.mkAlloyAgent {
        hostName = config.networking.hostName;
        monitoringLocalAddress = config.vars.network.containers.monitoring.localAddress;
        extraGroups =
          lib.optionals (config.services.nginx.enable or false) [ "nginx" ]
          ++ lib.optionals (config.services.adguardhome.enable or false) [ "adguardhome" ];
      })
    ];
  };
}
