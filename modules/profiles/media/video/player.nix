{
  flake.nixosModules.profiles-media-video-player =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-lg-devmode-extend
      ];
    };
}
