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
        publishPorts = [ "127.0.0.1:3333:3333" ];
        logDriver = "journald";
        environments = {
          TZ = "UTC";
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
