{
  flake.nixosModules.services-home-automation-music-assistant = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.music-assistant = {
      containerConfig = {
        image = "ghcr.io/music-assistant/server:2.11.0b0";
        publishPorts = [
          "127.0.0.1:8095:8095"
        ];
        logDriver = "journald";
        environments = {
          TZ = "UTC";
        };
      };
    };

    environment.etc."alloy/music-assistant.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "music-assistant";
      id = "music_assistant";
      hostName = config.networking.hostName;
    };
  };
}
