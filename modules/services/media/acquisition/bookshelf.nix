{
  flake.nixosModules.services-media-acquisition-bookshelf =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.bookshelf = {
        containerConfig = {
          image = "ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.21.182";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            PUID = "1000";
            PGID = "2000";
            TZ = "UTC";
            METADATA_URL = "http://${config.vars.network.podmanAddresses.rreading-glasses}:8788";
          };
          environmentFiles = [ config.sops.templates."media.bookshelf.env".path ];
        }
        // flakeLib.quadlet.mkHealthCheck { port = 8787; };
      };

      environment.etc."alloy/bookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "bookshelf";
        hostName = config.networking.hostName;
      };
    };
}
