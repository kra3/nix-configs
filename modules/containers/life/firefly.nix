{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.life;
in
{
  sops.secrets."life.firefly.app_key" = {};
  sops.secrets."life.firefly.cron_token" = {};

  sops.templates."life.firefly.env" = {
    owner = "root";
    group = "media";
    mode = "0440";
    content = ''
      APP_ENV=production
      APP_DEBUG=false
      APP_URL=https://firefly.${config.vars.acme.domain}
      SITE_OWNER=${config.vars.acme.email}
      TRUSTED_PROXIES=**
      DB_CONNECTION=pgsql
      DB_HOST=host.containers.internal
      DB_PORT=5432
      DB_DATABASE=firefly
      DB_USERNAME=firefly
      DB_PASSWORD=${config.sops.placeholder."db.firefly_password"}
      PGSQL_SSL_MODE=disable
      PGSQL_SCHEMA=public
      CACHE_DRIVER=file
      SESSION_DRIVER=file
      COOKIE_SECURE=true
      DKR_CHECK_SQLITE=false
      APP_KEY_FILE=${config.sops.secrets."life.firefly.app_key".path}
      STATIC_CRON_TOKEN_FILE=${config.sops.secrets."life.firefly.cron_token".path}
    '';
  };

  virtualisation.quadlet.containers.firefly = {
    containerConfig = {
      image = "fireflyiii/core:6.2.12";
      healthCmd = "wget -qO- http://localhost:8080/health";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "60s";
      publishPorts = [ "127.0.0.1:8888:8080" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."life.firefly.env".path ];
      volumes = [
        "/srv/appdata/life/firefly/upload:/var/www/html/storage/upload"
        "${config.sops.secrets."life.firefly.app_key".path}:${config.sops.secrets."life.firefly.app_key".path}:ro"
        "${config.sops.secrets."life.firefly.cron_token".path}:${config.sops.secrets."life.firefly.cron_token".path}:ro"
      ];
    };
    unitConfig = {
      After = [ "life-network.service" "postgresql-set-passwords.service" ];
      Requires = [ "life-network.service" "postgresql-set-passwords.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/firefly.alloy".text = ''
    loki.source.journal "firefly" {
      matches = "_SYSTEMD_UNIT=firefly.service"
      labels = {
        job = "firefly",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."firefly.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8888";
      proxyWebsockets = true;
    };
  };
}
