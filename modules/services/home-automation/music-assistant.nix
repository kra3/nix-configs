{
  flake.nixosModules.services-home-automation-music-assistant =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.music-assistant = {
        containerConfig = {
          image = "ghcr.io/music-assistant/server:2.10.13@sha256:7510aaa7ee5fc85b34fd0de17992bd14473895b23ce3eb9b310092743f4dbb84";
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
