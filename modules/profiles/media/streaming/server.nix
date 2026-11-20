{
  flake.nixosModules.profiles-media-streaming-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-media-mgmt-aiostreams
        flakeModules.nixos.containers-media-mgmt-aiometadata
      ];
    };
}
