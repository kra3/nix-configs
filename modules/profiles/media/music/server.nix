{
  flake.nixosModules.profiles-media-music-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-home-auto-music-assistant-default
      ];
    };
}
