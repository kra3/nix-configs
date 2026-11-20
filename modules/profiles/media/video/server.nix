{
  flake.nixosModules.profiles-media-video-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-play
        flakeModules.nixos.services-media-streaming-iptv
      ];
    };
}
