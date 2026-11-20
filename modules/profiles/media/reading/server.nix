{
  flake.nixosModules.profiles-media-reading-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-media-mgmt-audiobookshelf
      ];
    };
}
