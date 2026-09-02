{
  flake.nixosModules.services-media-acquisition-unpackerr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.unpackerr = {
      containerConfig = {
        image = "ghcr.io/unpackerr/unpackerr:v0.16.1";
        publishPorts = [ "127.0.0.1:5656:5656" ];
        logDriver = "journald";
        user = "1000:2000";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.unpackerr.env".path ];
      }
      // flakeLib.quadlet.mkHealthCheck {
        port = 5656;
        # unpackerr has no /api/v1/health route (confirmed 404 in its access
        # log); its webserver only serves "/" (200 "Welcome!") and, since
        # UN_WEBSERVER_METRICS=true above, "/metrics".
        path = "";
      };
    };

    environment.etc."alloy/unpackerr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "unpackerr";
      hostName = config.networking.hostName;
    };
  };
}
