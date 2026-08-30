{
  flake.nixosModules.services-finance-actualbudget = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.actualbudget = {
      containerConfig = {
        image = "actualbudget/actual-server:26.8.1";
        # No publishPorts: see services/media/acquisition/radarr.nix — nginx
        # routes to a pinned bridge IP instead (set at the call site).
        logDriver = "journald";
        environments = {
          TZ = "UTC";
          ACTUAL_HOSTNAME = "0.0.0.0";
        };
      };
    };

    environment.etc."alloy/actualbudget.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "actualbudget";
      hostName = config.networking.hostName;
    };
  };
}
