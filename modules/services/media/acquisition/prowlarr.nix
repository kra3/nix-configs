{
  flake.nixosModules.services-media-acquisition-prowlarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.prowlarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/prowlarr:3.0.2.5780-ls169@sha256:45117ba8439e2337a92ffe38a451a4dafc0be771754d05d88cdf102419d09646";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            PUID = "1000";
            PGID = "2000";
            TZ = "UTC";
          };
          environmentFiles = [ config.sops.templates."media.prowlarr.env".path ];
        }
        // flakeLib.quadlet.mkHealthCheck { port = 9696; };
      };

      environment.etc."alloy/prowlarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "prowlarr";
        hostName = config.networking.hostName;
      };
    };
}
