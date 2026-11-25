{
  flake.nixosModules.services-media-acquisition-prowlarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.prowlarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/prowlarr:3.1.0.5799-ls170@sha256:2806c9b763810589c42157730d547c293639e55c7610e9f5069314854639ec48";
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
