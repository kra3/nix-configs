{
  flake.nixosModules.services-media-acquisition-recyclarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.recyclarr = {
        containerConfig = {
          image = "ghcr.io/recyclarr/recyclarr:8.8.1@sha256:3e9c41b9ec29bbf65fe846864058730d321a21f7695d8c0d9437b73e34d50ad9";
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
