{
  flake.nixosModules.services-media-acquisition-lidarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.lidarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/lidarr:nightly-4.0.0.5227-ls227@sha256:969a82b8374db468eb9f68ce3cec88c747b5a9cda28f00fa617ee45c9e8e76c0";
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
