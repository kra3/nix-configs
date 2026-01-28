{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.nginxAllowCidrs)}
    deny all;
  '';
in
{
  services.nginx.virtualHosts."jellyfin.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.6:8096";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."navidrome.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.6:4533";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."mass.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.6:8095";
      proxyWebsockets = true;
    };
  };
}