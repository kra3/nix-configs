{
  flake.nixosModules.services-media-streaming-aiostreams = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.aiostreams = {
      containerConfig = {
        image = "ghcr.io/viren070/aiostreams:v2.34.0";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        # No healthcheck: no documented health endpoint to pin to.
        logDriver = "journald";
        environments = {
          BASE_URL = "https://aiostreams.${config.vars.acme.domain}";
          DATABASE_URI = "sqlite://./data/db.sqlite";
          # Dashboard-only SSO (never gates Stremio addon URLs); client secret
          # is set via the env file instead (see media-mgmt/aiostreams.nix).
          AIOSTREAMS_OIDC_ENABLED = "true";
          AIOSTREAMS_OIDC_ISSUER = "https://auth.${config.vars.acme.domain}";
          AIOSTREAMS_OIDC_CLIENT_ID = "aiostreams";
          AIOSTREAMS_OIDC_SCOPES = "openid,profile,email,groups";
          # Only admin group logs in via SSO; family is refused (debrid/usenet creds, not user-land).
          AIOSTREAMS_OIDC_GROUP_PERMISSIONS = "admin=admin";
          # Avoids collision with the local AIOSTREAMS_AUTH user of the same name (kra3).
          AIOSTREAMS_OIDC_USERNAME_PREFIX = "sso:";
        };
        environmentFiles = [ config.sops.templates."media.aiostreams.env".path ];
      };
    };

    environment.etc."alloy/aiostreams.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "aiostreams";
      hostName = config.networking.hostName;
    };
  };
}
