{
  flake.nixosModules.services-media-acquisition-audiobookshelf =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.audiobookshelf = {
        containerConfig = {
          image = "ghcr.io/advplyr/audiobookshelf:2.36.0";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            TZ = "UTC";
          };
        }
        // flakeLib.quadlet.mkHealthCheck {
          port = 80;
          path = "healthcheck";
        };
      };

      environment.etc."alloy/audiobookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "audiobookshelf";
        hostName = config.networking.hostName;
      };
    };
}
