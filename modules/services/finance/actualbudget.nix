{
  flake.nixosModules.services-finance-actualbudget =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.actualbudget = {
        containerConfig = {
          image = "docker.io/actualbudget/actual-server:26.11.0@sha256:06cf186569cf58d93e12659ff1a517b65b5b0ebee7050a3991d4bd8a1d398da6";
          user = "2402:2402";
          dropCapabilities = [ "ALL" ];
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
