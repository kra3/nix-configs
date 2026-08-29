{
  flake.nixosModules.services-media-acquisition-bookshelf = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.bookshelf = {
      containerConfig = {
        image = "ghcr.io/pennydreadful/bookshelf:hardcover-v0.4.20.129";
        publishPorts = [ "127.0.0.1:8787:8787" ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.bookshelf.env".path ];
      } // flakeLib.quadlet.mkHealthCheck { port = 8787; };
    };

    environment.etc."alloy/bookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "bookshelf";
      hostName = config.networking.hostName;
    };
  };
}
