{
  flake.nixosModules.services-media-acquisition-lidarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.lidarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/lidarr:3.1.0.4875-ls40";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.lidarr.env".path ];
      } // flakeLib.quadlet.mkHealthCheck { port = 8686; };
    };

    environment.etc."alloy/lidarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "lidarr";
      hostName = config.networking.hostName;
    };
  };
}
