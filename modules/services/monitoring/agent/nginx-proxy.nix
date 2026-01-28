{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.nginxAllowCidrs)}
    deny all;
  '';
in
{
  services.nginx.virtualHosts."grafana.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.0.50.2:3001";
      proxyWebsockets = true;
    };
  };


  sops.secrets."monitoring.grafana.admin.user" = {
    mode = "0444";
  };
  sops.secrets."monitoring.grafana.admin.password" = {
    mode = "0444";
  };
}