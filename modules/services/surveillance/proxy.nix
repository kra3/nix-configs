{ config, lib, flakeLib, ... }:
let
  homeAutoIp = config.containers.home-auto.localAddress or "10.0.50.8";
in
{
  services.nginx.virtualHosts."z2m.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://${homeAutoIp}:8080";
  };

  services.nginx.virtualHosts."nvr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
    domain = config.vars.acme.domain;
    cidrs = config.vars.network.nginxAllowCidrs;
    upstream = "http://${homeAutoIp}:80";
  };
}
