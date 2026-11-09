{
  flake.nixosModules.services-finance-ghostfolio-ghostfolio =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.ghostfolio = {
        containerConfig = {
          image = "docker.io/ghostfolio/ghostfolio:3.98.0";
          healthCmd = "i=0; while [ $i -lt 12 ]; do curl -sf http://localhost:3333/api/v1/health && exit 0; sleep 2; i=$((i+1)); done; exit 1";
          healthOnFailure = "none";
          healthInterval = "60s";
          healthTimeout = "55s";
          healthRetries = 3;
          healthStartPeriod = "60s";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            TZ = "UTC";
            # Forces a restart on env content changes — see authelia.nix's
            # RESTART_TRIGGER_CONFIG_HASH for why this is needed.
            RESTART_TRIGGER_CONFIG_HASH =
              builtins.hashString "sha256"
                config.sops.templates."life.ghostfolio.env".content;
          };
          environmentFiles = [ config.sops.templates."life.ghostfolio.env".path ];
        };
      };

      environment.etc."alloy/ghostfolio.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "ghostfolio";
        hostName = config.networking.hostName;
      };
    };
}
