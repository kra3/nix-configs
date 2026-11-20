{
  flake.nixosModules.profiles-media-music-player =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-media-sendspin
      ];
    };
}
