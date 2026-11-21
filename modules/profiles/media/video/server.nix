{
  flake.nixosModules.profiles-media-video-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-play
        flakeModules.nixos.services-media-streaming-iptv
      ];

      # Jellyfin lives in the media-play container; this profile switches it on.
      containers.media-play.config.services.declarative-jellyfin.enable = true;
    };
}
