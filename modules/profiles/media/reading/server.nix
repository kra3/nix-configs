{
  flake.nixosModules.profiles-media-reading-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-audiobookshelf
      ];
    };
}
