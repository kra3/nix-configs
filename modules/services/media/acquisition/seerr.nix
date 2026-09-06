{
  flake.nixosModules.services-media-acquisition-seerr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.seerr = {
        containerConfig = {
          image = "ghcr.io/seerr-team/seerr:v3.4.1";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            PUID = "1000";
            PGID = "2000";
            TZ = "UTC";
          };
          environmentFiles = [ config.sops.templates."media.seerr.env".path ];
        }
        // flakeLib.quadlet.mkHealthCheck {
          port = 5055;
          path = "api/v1/status";
          startPeriod = "60s";
        };
      };

      environment.etc."alloy/seerr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "seerr";
        hostName = config.networking.hostName;
      };
    };
}
