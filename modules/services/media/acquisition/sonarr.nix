{
  flake.nixosModules.services-media-acquisition-sonarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.sonarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/sonarr:4.0.19.2979-ls321";
        publishPorts = [ "127.0.0.1:8989:8989" ];
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
