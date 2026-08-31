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
