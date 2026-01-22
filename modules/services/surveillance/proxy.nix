{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.nginxAllowCidrs)}
    deny all;
  '';
  homeAutoIp = config.containers.home-auto.localAddress or "10.0.50.8";
in
{
  services.nginx.virtualHosts."frigate.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:80";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."go2rtc.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:1984";
      proxyWebsockets = true;
    };
  };
}
