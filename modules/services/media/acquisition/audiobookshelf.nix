{
  flake.nixosModules.services-media-acquisition-audiobookshelf =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.audiobookshelf = {
        containerConfig = {
          image = "ghcr.io/advplyr/audiobookshelf:v3@sha256:d68b6e90df9634ffd16b7c6ec84e3a51879e56ff1dfe6041edee2f36f3e2e191";
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
