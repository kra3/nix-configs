{
  flake.nixosModules.services-finance-ghostfolio-ghostfolio = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.ghostfolio = {
      containerConfig = {
        image = "ghostfolio/ghostfolio:3.63.0";
        healthCmd = "curl -sf http://localhost:3333/api/v1/health";
        healthOnFailure = "none";
        healthInterval = "30s";
        healthTimeout = "10s";
        healthRetries = 3;
        healthStartPeriod = "60s";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        logDriver = "journald";
        environments = {
          TZ = "UTC";
          # Forces a restart on env content changes — see authelia.nix's
          # RESTART_TRIGGER_CONFIG_HASH for why this is needed.
          RESTART_TRIGGER_CONFIG_HASH = builtins.hashString "sha256" config.sops.templates."life.ghostfolio.env".content;
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
