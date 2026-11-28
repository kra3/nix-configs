{
  flake.nixosModules.services-media-acquisition-recyclarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.recyclarr = {
        containerConfig = {
          image = "ghcr.io/recyclarr/recyclarr:9.0.0@sha256:4973d11b18b5ef09fb226f4161eecb16434ff7e6b43c56d50fceb52fb22c66c7";
          logDriver = "journald";
          # Image ignores PUID/PGID and defaults to 1000:1000, which can't write /config (2770 root:media).
          user = "1000:2000";
          environments = {
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
