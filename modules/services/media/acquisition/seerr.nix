{
  flake.nixosModules.services-media-acquisition-seerr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.seerr = {
        containerConfig = {
          image = "ghcr.io/seerr-team/seerr:v3.5.2@sha256:aadee014b40e28cf9aa4928bc9d1183a6eb08f8c44d543cddc9efdcb16549be2";
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
