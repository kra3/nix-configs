{
  flake.nixosModules.profiles-media-reading-acquire =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-media-mgmt-bookshelf
        flakeModules.nixos.containers-media-mgmt-rreading-glasses
      ];
    };
}
