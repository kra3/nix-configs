{
  flake.nixosModules.services-home-automation-wyoming-piper = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.wyoming-piper = {
      containerConfig = {
        image = "docker.io/rhasspy/wyoming-piper:2.4.2";
        exec = "--voice en_US-lessac-medium --uri tcp://0.0.0.0:10200 --data-dir /data --download-dir /data";
        logDriver = "journald";
        environments = {
          TZ = "UTC";
        };
      };
    };

    environment.etc."alloy/wyoming-piper.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "wyoming-piper";
      id = "wyoming_piper";
      hostName = config.networking.hostName;
    };
  };
}
