{
  flake.nixosModules.services-media-streaming-aiostreams = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.aiostreams = {
      containerConfig = {
        image = "ghcr.io/viren070/aiostreams:v2.33.2";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        # No healthcheck: no documented health endpoint to pin to.
        logDriver = "journald";
        environments = {
          BASE_URL = "https://aiostreams.${config.vars.acme.domain}";
          DATABASE_URI = "sqlite://./data/db.sqlite";
          # Dashboard/config-page SSO only — never gates the Stremio addon
          # URLs (AIOStreams' own doc note). AIOSTREAMS_OIDC_CLIENT_SECRET is
          # secret, set via the env file instead (see media-mgmt/aiostreams.nix).
          AIOSTREAMS_OIDC_ENABLED = "true";
          AIOSTREAMS_OIDC_ISSUER = "https://auth.${config.vars.acme.domain}";
          AIOSTREAMS_OIDC_CLIENT_ID = "aiostreams";
          AIOSTREAMS_OIDC_SCOPES = "openid,profile,email,groups";
          # Only the admin group can log into the dashboard; family (no
          # entry here) is refused — this is a debrid/usenet-credential
          # config surface, not a user-land app.
          AIOSTREAMS_OIDC_GROUP_PERMISSIONS = "admin=admin";
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
