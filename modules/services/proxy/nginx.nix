{ config, lib, ... }:
let
  serviceLib = import ../../lib { inherit lib config; };
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
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
      proxy_headers_hash_max_size 1024;
      proxy_headers_hash_bucket_size 128;
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

  systemd.services.nginx.serviceConfig = lib.mkMerge [
    (serviceLib.deployment.hardening.mkServiceSandbox {
      readWritePaths = [ "/var/log/nginx" ];
      capabilities = [ "CAP_NET_BIND_SERVICE" ];
    })
  ];

  networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [
    443
  ];

  services.logrotate.settings.nginx = {
    files = [
      "/var/log/nginx/*.log"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "nginx nginx";
  };

  environment.etc."alloy/config.alloy".text = lib.mkAfter ''
    loki.source.file "nginx" {
      targets = [
        {
          __path__ = "/var/log/nginx/access.log",
          job = "nginx",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
        {
          __path__ = "/var/log/nginx/error.log",
          job = "nginx",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
