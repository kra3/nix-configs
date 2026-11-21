{
  flake.nixosModules.profiles-media-video-acquire =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-radarr
        flakeModules.nixos.containers-media-mgmt-sonarr
        flakeModules.nixos.containers-media-mgmt-recyclarr
        flakeModules.nixos.containers-media-mgmt-maintainerr
        flakeModules.nixos.containers-media-mgmt-seerr
      ];
    };
}
