{
  flake.nixosModules.services-media-acquisition-audiobookshelf = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.audiobookshelf = {
      containerConfig = {
        image = "ghcr.io/advplyr/audiobookshelf:2.36.0";
        publishPorts = [ "127.0.0.1:13378:80" ];
        logDriver = "journald";
        environments = {
          TZ = "UTC";
        };
      } // flakeLib.quadlet.mkHealthCheck { port = 80; path = "healthcheck"; };
    };

    environment.etc."alloy/audiobookshelf.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "audiobookshelf";
      hostName = config.networking.hostName;
    };
  };
}
