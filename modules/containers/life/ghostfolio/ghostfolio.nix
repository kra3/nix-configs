{
  flake.nixosModules.containers-life-ghostfolio-ghostfolio = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.life;
  in
  {
    imports = [ flakeModules.nixos.services-finance-ghostfolio-ghostfolio ];

    sops.secrets."life.ghostfolio.access_token" = { };
    sops.secrets."life.ghostfolio.jwt_secret" = { };

    sops.templates."life.ghostfolio.env" = {
      owner = "root";
      group = "life";
      mode = "0440";
      content = ''
        NODE_ENV=production
        POSTGRES_DB=ghostfolio
        POSTGRES_USER=ghostfolio
        POSTGRES_PASSWORD=${config.sops.placeholder."db.ghostfolio_password"}
        DATABASE_URL=postgresql://ghostfolio:${
          config.sops.placeholder."db.ghostfolio_password"
        }@host.containers.internal:5432/ghostfolio?connect_timeout=300
        REDIS_HOST=host.containers.internal
        REDIS_PORT=6379
        REDIS_PASSWORD=${config.sops.placeholder."db.redis_password"}
        ACCESS_TOKEN_SALT=${config.sops.placeholder."life.ghostfolio.access_token"}
        JWT_SECRET_KEY=${config.sops.placeholder."life.ghostfolio.jwt_secret"}
      '';
    };

    virtualisation.quadlet.containers.ghostfolio = {
      containerConfig = {
        networks = [ network.ref ];
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "life-network.service" ];
      extraAfter = [ "postgresql-set-passwords.service" "redis-default.service" ];
      extraRequires = [ "postgresql-set-passwords.service" "redis-default.service" ];
    };

    services.nginx.virtualHosts."ghostfolio.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:3333";
    };
  };
}
