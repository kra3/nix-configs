{
  flake.nixosModules.services-media-acquisition-sonarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.sonarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/sonarr:4.0.19.2979-ls321";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.sonarr.env".path ];
      } // flakeLib.quadlet.mkHealthCheck { port = 8989; };
    };

    environment.etc."alloy/sonarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "sonarr";
      hostName = config.networking.hostName;
    };
  };
}
