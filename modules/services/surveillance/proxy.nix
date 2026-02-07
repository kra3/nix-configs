{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.nginxAllowCidrs)}
    deny all;
  '';
  homeAutoIp = config.containers.home-auto.localAddress or "10.0.50.8";
in
{
  services.nginx.virtualHosts."z2m.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:8080";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."nvr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:80";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."ha2.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      ${allowBlock}
      client_max_body_size 500m;
    '';
    locations."/" = {
      proxyPass = "http://${homeAutoIp}:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
      '';
    };
  };
}
