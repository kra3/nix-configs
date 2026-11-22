{
  flake.nixosModules.services-media-acquisition-audiobookshelf =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.audiobookshelf = {
        containerConfig = {
          image = "ghcr.io/advplyr/audiobookshelf:v3@sha256:8e0027860a9ab59ecaadf9f27f270a304dfbc539ea58b9981c75a24c1828e657";
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
