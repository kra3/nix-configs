{
  flake.nixosModules.profiles-media-reading-acquire =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-bookshelf
        flakeModules.nixos.containers-media-mgmt-rreading-glasses
      ];
    };
}
