{
  flake.nixosModules.profiles-media-music-acquire =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-lidarr
        flakeModules.nixos.containers-media-mgmt-slskd
        flakeModules.nixos.services-media-lidarr-beets-webhook
        flakeModules.nixos.services-media-lidarr-failed-import-recovery
      ];
    };
}
