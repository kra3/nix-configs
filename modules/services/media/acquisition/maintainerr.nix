{
  flake.nixosModules.services-media-acquisition-maintainerr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.maintainerr = {
      containerConfig = {
        image = "ghcr.io/maintainerr/maintainerr:3.23.0";
        publishPorts = [ "127.0.0.1:6246:6246" ];
        logDriver = "journald";
        user = "1000:2000";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
      }
      // flakeLib.quadlet.mkHealthCheck {
        port = 6246;
        path = "healthcheck";
        startPeriod = "60s";
      };
    };

    environment.etc."alloy/maintainerr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "maintainerr";
      hostName = config.networking.hostName;
    };
  };
}
