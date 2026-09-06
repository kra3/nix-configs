{
  flake.nixosModules.services-media-acquisition-prowlarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.prowlarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/prowlarr:2.5.2.5491-ls158";
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
