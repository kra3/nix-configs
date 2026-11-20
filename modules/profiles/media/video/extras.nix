{
  flake.nixosModules.profiles-media-video-extras =
    { flakeModules, ... }:
    {
      # bazarr and unpackerr expect radarr/sonarr from profiles-media-video-acquire.
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-bazarr
        flakeModules.nixos.containers-media-mgmt-unpackerr
      ];
    };
}
