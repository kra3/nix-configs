{
  flake.nixosModules.services-media-acquisition-lidarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.lidarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/lidarr:nightly-4.0.0.5236-ls228@sha256:656a4d008a9a60ba32aba95c85b0fd19a06af8e2680f6748ef693956aa84ae33";
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
