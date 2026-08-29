{
  flake.nixosModules.services-media-acquisition-prowlarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.prowlarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/prowlarr:2.5.2.5491-ls157";
        publishPorts = [ "127.0.0.1:9696:9696" ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.prowlarr.env".path ];
      } // flakeLib.quadlet.mkHealthCheck { port = 9696; };
    };

    environment.etc."alloy/prowlarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "prowlarr";
      hostName = config.networking.hostName;
    };
  };
}
