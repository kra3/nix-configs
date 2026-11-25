{
  flake.nixosModules.profiles-media-music-server =
    { flakeModules, ... }:
    {
      # Relies on media-play (imported by profiles-media-video-server); Navidrome lives inside it.
      imports = [
        flakeModules.nixos.containers-home-auto-music-assistant-default
        flakeModules.nixos.services-media-streaming-radio
      ];
    };
}
