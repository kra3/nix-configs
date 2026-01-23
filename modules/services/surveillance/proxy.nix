{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.nginxAllowCidrs)}
    deny all;
  '';
  homeAutoIp = config.containers.home-auto.localAddress or "10.0.50.8";
in
{
  services.nginx.virtualHosts."nvr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:80";
      proxyWebsockets = true;
    };
    locations."/api/metrics" = {
      proxyPass = "http://${homeAutoIp}:80/api/metrics";
      extraConfig = ''
        allow 10.0.50.2;
        deny all;
        access_log off;
        add_header Cache-Control "no-store";
      '';
    };
  };
}
