{
  flake.nixosModules.profiles-media-video-extras =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-bazarr
        flakeModules.nixos.containers-media-mgmt-unpackerr
      ];
    };
}
