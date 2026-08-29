{
  flake.nixosModules.services-media-acquisition-bazarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.bazarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/bazarr:v1.6.0-ls361";
        publishPorts = [ "127.0.0.1:6767:6767" ];
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
