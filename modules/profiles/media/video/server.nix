{
  flake.nixosModules.profiles-media-video-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-media-play
        flakeModules.nixos.services-media-streaming-iptv
      ];
    };
}
