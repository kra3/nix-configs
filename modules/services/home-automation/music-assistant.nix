{
  flake.nixosModules.services-home-automation-music-assistant =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.music-assistant = {
        containerConfig = {
          image = "ghcr.io/music-assistant/server:2.10.14@sha256:7a2c25e78ed47ee2752c6b6e0667e561f9c40195dd1f017d0adf20dedb7ad8e0";
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
