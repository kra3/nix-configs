{
  flake.nixosModules.services-media-acquisition-sabnzbd = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.sabnzbd = {
      containerConfig = {
        image = "lscr.io/linuxserver/sabnzbd:5.1.1-ls267";
        publishPorts = [ "127.0.0.1:8080:8080" ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
          HAS_IPV6 = "false";
        };
        environmentFiles = [ config.sops.templates."media.sabnzbd.env".path ];
      }
      // flakeLib.quadlet.mkHealthCheck {
        port = 8080;
        path = "api?mode=version";
        startPeriod = "60s";
      };
    };

    environment.etc."alloy/sabnzbd.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "sabnzbd";
      hostName = config.networking.hostName;
    };
  };
}
