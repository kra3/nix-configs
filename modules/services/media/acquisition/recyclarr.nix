{
  flake.nixosModules.services-media-acquisition-recyclarr = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.recyclarr = {
      containerConfig = {
        image = "ghcr.io/recyclarr/recyclarr:8.7.1";
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
      };
    };

    environment.etc."alloy/recyclarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "recyclarr";
      hostName = config.networking.hostName;
    };
  };
}
