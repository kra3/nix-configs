{
  flake.nixosModules.services-media-streaming-aiometadata =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.aiometadata = {
        containerConfig = {
          image = "ghcr.io/cedya77/aiometadata:3.4.0";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            PORT = "3232";
            NODE_ENV = "production";
            HOST_NAME = "https://aiometadata.${config.vars.acme.domain}";
            DATABASE_URI = "sqlite://addon/data/db.sqlite";
            ENABLE_BUILTIN_POSTER_CACHE = "true";
            REDIS_AUTOTUNE = "false";
            ENABLE_AI_SEARCH = "true";
            JIKAN_API_BASE = "https://jikanfortheweebs.midnightignite.me/v4";
            INCLUDE_ADULT = "true";
            # Dashboard-only SSO; client secret comes from the env file (see media-mgmt/aiometadata.nix).
            OIDC_ENABLED = "true";
            OIDC_ISSUER = "https://auth.${config.vars.acme.domain}";
            OIDC_CLIENT_ID = "aiometadata";
            OIDC_GROUP_PERMISSIONS = "admin=admin";
          };
          environmentFiles = [ config.sops.templates."media.aiometadata.env".path ];
        };
      };

      environment.etc."alloy/aiometadata.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "aiometadata";
        hostName = config.networking.hostName;
      };
    };
}
