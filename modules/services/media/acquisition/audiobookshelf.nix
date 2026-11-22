{
  flake.nixosModules.services-media-acquisition-audiobookshelf =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.audiobookshelf = {
        containerConfig = {
          image = "ghcr.io/advplyr/audiobookshelf:v3@sha256:843c41e9bf8936793ec782e905b5f41d92e7023d28a8a3fc0f1355df6873a0c1";
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
