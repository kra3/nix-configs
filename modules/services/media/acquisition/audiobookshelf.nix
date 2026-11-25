{
  flake.nixosModules.services-media-acquisition-audiobookshelf =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.audiobookshelf = {
        containerConfig = {
          image = "ghcr.io/advplyr/audiobookshelf:v3@sha256:6947e015fa8e9c19c247739106c76ba99270ca3e2b4b7daf97f1f621ff173f60";
          user = "1000:2000";
          dropCapabilities = [ "ALL" ];
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            TZ = "UTC";
            PORT = "8080";
          };
        }
        // flakeLib.quadlet.mkHealthCheck {
          port = 8080;
          path = "healthcheck";
        };
      };

      environment.etc."alloy/audiobookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "audiobookshelf";
        hostName = config.networking.hostName;
      };
    };
}
