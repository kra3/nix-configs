{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  homeAutoIp = config.containers.home-auto.localAddress or "10.0.50.8";
in
{
  services.nginx.virtualHosts."z2m.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:8080";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."nvr.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:80";
      proxyWebsockets = true;
    };
  };
}
