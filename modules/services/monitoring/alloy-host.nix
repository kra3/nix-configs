{ config, lib, ... }:
let
  containerLib = import ../../lib { inherit lib; };
in
{
  imports = [
    (containerLib.observability.mkAlloyAgent {
      hostName = config.networking.hostName;
      monitoringLocalAddress = config.vars.network.containers.monitoring.localAddress;
      extraGroups =
        lib.optionals (config.services.nginx.enable or false) [ "nginx" ]
        ++ lib.optionals (config.services.adguardhome.enable or false) [ "adguardhome" ];
    })
  ];
}
