{
  flake.nixosModules.services-media-acquisition-slskd =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.slskd = {
        containerConfig = {
          image = "slskd/slskd:0.26.2@sha256:d0963a3e5b16facd295bf4f2156dad0182f246b1b21a032cae12f5494c694843";
          user = "1000:2000";
          logDriver = "journald";
          # Only the Soulseek P2P listen port is published to the host/WAN —
          # the web UI (5030) stays bridge-only, reached via nginx like every
          # other app here (see containers/media-mgmt/slskd.nix).
          publishPorts = [ "50300:50300" ];
          environments = {
            SLSKD_SLSK_LISTEN_PORT = "50300";
            SLSKD_REMOTE_CONFIGURATION = "false";
          };
          environmentFiles = [ config.sops.templates."media.slskd.env".path ];
          # Genuinely internet-facing (P2P listen port), unlike the rest of
          # this stack which sits behind Authelia — drop everything not needed.
          dropCapabilities = [ "ALL" ];
        }
        // flakeLib.quadlet.mkHealthCheck {
          port = 5030;
          path = "health";
        };
      };

      environment.etc."alloy/slskd.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "slskd";
        hostName = config.networking.hostName;
      };
    };
}
