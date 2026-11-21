{
  flake.nixosModules.services-media-acquisition-radarr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.radarr = {
        containerConfig = {
          image = "lscr.io/linuxserver/radarr:7.0.3.10918-ls328@sha256:044788f5508b7f67a3e0368cdd142c77c4d4cd5aec2efaba53e1a68b6b6231e7";
          # No publishPorts: nginx runs on the host and already routes to the
          # br-media-mgmt subnet directly (a static IP, set at the call site),
          # so a host-loopback port isn't needed and would let any host-local
          # process bypass Authelia's forward-auth by hitting it directly.
          logDriver = "journald";
          environments = {
            PUID = "1000";
            PGID = "2000";
            TZ = "UTC";
          };
          environmentFiles = [ config.sops.templates."media.radarr.env".path ];
        }
        // flakeLib.quadlet.mkHealthCheck { port = 7878; };
      };

      environment.etc."alloy/radarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "radarr";
        hostName = config.networking.hostName;
      };
    };
}
