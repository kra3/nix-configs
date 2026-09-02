{
  flake.nixosModules.services-media-acquisition-bazarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.bazarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/bazarr:438eee94-ls46";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.bazarr.env".path ];
      } // flakeLib.quadlet.mkHealthCheck { port = 6767; };
    };

    environment.etc."alloy/bazarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "bazarr";
      hostName = config.networking.hostName;
    };
  };
}
