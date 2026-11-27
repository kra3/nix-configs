{
  flake.nixosModules.services-media-acquisition-lidarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.lidarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/lidarr:nightly-4.0.0.5247-ls230@sha256:0db4488f80216a822949a1f4a85f10bb27d742003a61398f0252f4ae3a03a891";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            PUID = "1000";
            PGID = "2000";
            TZ = "UTC";
          };
          environmentFiles = [ config.sops.templates."media.lidarr.env".path ];
        }
        // flakeLib.quadlet.mkHealthCheck { port = 8686; };
      };

      environment.etc."alloy/lidarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "lidarr";
        hostName = config.networking.hostName;
      };
    };
}
