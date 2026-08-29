{
  flake.nixosModules.services-media-acquisition-radarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.radarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/radarr:6.3.0.10514-ls313";
        publishPorts = [ "127.0.0.1:7878:7878" ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.radarr.env".path ];
      } // flakeLib.quadlet.mkHealthCheck { port = 7878; };
    };

    environment.etc."alloy/radarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "radarr";
      hostName = config.networking.hostName;
    };
  };
}
