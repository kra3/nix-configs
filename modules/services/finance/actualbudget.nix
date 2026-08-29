{
  flake.nixosModules.services-finance-actualbudget = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.actualbudget = {
      containerConfig = {
        image = "actualbudget/actual-server:26.8.1";
        publishPorts = [ "127.0.0.1:5006:5006" ];
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
