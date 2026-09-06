{
  flake.nixosModules.containers-life-ghostfolio-ghostfolio =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.life;
      ip = config.vars.network.podmanAddresses.ghostfolio;
    in
    {
      imports = [ flakeModules.nixos.services-finance-ghostfolio-ghostfolio ];

      sops.secrets."life.ghostfolio.access_token" = { };
      sops.secrets."life.ghostfolio.jwt_secret" = { };
      sops.secrets."life.ghostfolio.oidc_client_secret" = { };

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
          ENABLE_FEATURE_AUTH_OIDC=true
          OIDC_ISSUER=https://auth.${config.vars.acme.domain}
          OIDC_CLIENT_ID=ghostfolio
          OIDC_CLIENT_SECRET=${config.sops.placeholder."life.ghostfolio.oidc_client_secret"}
          # Needed so the OIDC redirect_uri is public, not the internal bind address.
          ROOT_URL=https://ghostfolio.${config.vars.acme.domain}
        '';
      };

      virtualisation.quadlet.containers.ghostfolio = {
        containerConfig = {
          # Pinned to its current dynamically-assigned IP — see
          # media-mgmt/radarr.nix for why. IP centralized in vars.nix
          # (podmanAddresses.ghostfolio).
          networks = [ "${network.ref}:ip=${ip}" ];
          # OIDC login calls auth.${domain} directly; route via the bridge
          # gateway since the LAN/public IP doesn't route back in from here.
          addHosts = [
            "auth.${config.vars.acme.domain}:10.3.0.1"
          ];
          # Sized from ~21h process-exporter peak (includes a nightly sync) + safety margin.
          memory = "1536m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps {
        networkServices = [ "life-network.service" ];
        extraAfter = [
          "postgresql-set-passwords.service"
          "redis-default.service"
        ];
        extraRequires = [
          "postgresql-set-passwords.service"
          "redis-default.service"
        ];
      };

      # No forwardAuth: authenticates natively via its own OIDC login (like Arcane).
      services.nginx.virtualHosts."ghostfolio.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:3333";
      };
    };
}
