{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.nginxAllowCidrs)}
    deny all;
  '';
in
{
  users.users.nginx.extraGroups = [ "acme" ];

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    commonHttpConfig = ''
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-Port $server_port;
    '';

    virtualHosts."karunagath.in" = {
      enableACME = true;
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        return = "404";
      };
    };

    virtualHosts."*.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        return = "404";
      };
    };

    virtualHosts."ha.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = allowBlock;
      locations."/" = {
        proxyPass = "http://192.168.1.31:8123";
        proxyWebsockets = true;
      };
    };

  };

  networking.firewall.interfaces.${config.vars.lanIf}.allowedTCPPorts = [
    443
  ];
}
