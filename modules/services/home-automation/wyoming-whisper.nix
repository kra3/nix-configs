{
  flake.nixosModules.services-home-automation-wyoming-whisper =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.wyoming-whisper = {
        containerConfig = {
          image = "docker.io/rhasspy/wyoming-whisper:3.9.0@sha256:3cc01f646c8b149fe47b2a5e8bfaf31866e1bc18faffadb26c9b8be58cbe5703";
          user = "1000:2000";
          dropCapabilities = [ "ALL" ];
          exec = "--model tiny-int8 --language en --uri tcp://0.0.0.0:10300 --data-dir /data --download-dir /data";
          logDriver = "journald";
          environments = {
            TZ = "UTC";
          };
        };
      };

      environment.etc."alloy/wyoming-whisper.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "wyoming-whisper";
        id = "wyoming_whisper";
        hostName = config.networking.hostName;
      };
    };
}
