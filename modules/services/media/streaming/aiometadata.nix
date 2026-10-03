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
