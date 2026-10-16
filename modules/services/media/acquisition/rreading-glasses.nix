{
  flake.nixosModules.services-media-acquisition-rreading-glasses =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.rreading-glasses = {
        containerConfig = {
          image = "docker.io/blampe/rreading-glasses:hardcover";
          # No publishPorts: bookshelf reaches it over the bridge at a pinned IP.
          logDriver = "journald";
          entrypoint = "/main";
          exec = "serve";
          environmentFiles = [ config.sops.templates."media.rreading-glasses.env".path ];
        };
      };

      environment.etc."alloy/rreading-glasses.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "rreading-glasses";
        hostName = config.networking.hostName;
      };
    };
}
