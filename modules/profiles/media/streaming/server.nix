{
  flake.nixosModules.profiles-media-streaming-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-aiostreams
        flakeModules.nixos.containers-media-mgmt-aiometadata
        flakeModules.nixos.services-redis
      ];
    };
}
