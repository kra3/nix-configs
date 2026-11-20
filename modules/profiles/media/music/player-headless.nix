{
  flake.nixosModules.profiles-media-music-player-headless =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-music-player
        flakeModules.nixos.services-media-pi-audio
      ];
    };
}
