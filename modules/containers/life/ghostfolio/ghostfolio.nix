{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.life;
in
{
  sops.secrets."life.ghostfolio.access_token" = {};
  sops.secrets."life.ghostfolio.jwt_secret" = {};

  sops.templates."life.ghostfolio.env" = {
    owner = "root";
    group = "life";
    mode = "0440";
    content = ''
      NODE_ENV=production
      POSTGRES_DB=ghostfolio
      POSTGRES_USER=ghostfolio
      POSTGRES_PASSWORD=${config.sops.placeholder."db.ghostfolio_password"}
      DATABASE_URL=postgresql://ghostfolio:${config.sops.placeholder."db.ghostfolio_password"}@host.containers.internal:5432/ghostfolio?connect_timeout=300
      REDIS_HOST=host.containers.internal
      REDIS_PORT=6379
      REDIS_PASSWORD=${config.sops.placeholder."db.redis_password"}
      ACCESS_TOKEN_SALT=${config.sops.placeholder."life.ghostfolio.access_token"}
      JWT_SECRET_KEY=${config.sops.placeholder."life.ghostfolio.jwt_secret"}
    '';
  };

  virtualisation.quadlet.containers.ghostfolio = {
    containerConfig = {
      image = "ghostfolio/ghostfolio:2.253.0";
      healthCmd = "wget -qO- http://localhost:3333/api/v1/health";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "60s";
      publishPorts = [ "127.0.0.1:3333:3333" ];
      networks = [ network.ref ];
      logDriver = "journald";
      environments = {
        TZ = "UTC";
      };
      environmentFiles = [ config.sops.templates."life.ghostfolio.env".path ];
    };
    unitConfig = {
      After = [ "life-network.service" "postgresql-set-passwords.service" "redis-default.service" ];
      Requires = [ "life-network.service" "postgresql-set-passwords.service" "redis-default.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/ghostfolio.alloy".text = ''
    loki.source.journal "ghostfolio" {
      matches = "_SYSTEMD_UNIT=ghostfolio.service"
      labels = {
        job = "ghostfolio",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."ghostfolio.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3333";
      proxyWebsockets = true;
    };
  };
}
