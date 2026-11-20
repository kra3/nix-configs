{
  flake.nixosModules.profiles-media-video-extras =
    { flakeModules, flakeLib, ... }:
    let
      gate = flakeLib.module-gate;
      localMediaExtras = config: config.vars.localMedia.enable && config.vars.localMedia.extras.enable;
    in
    {
      imports = [
        (gate localMediaExtras flakeModules.nixos.containers-media-mgmt-bazarr)
        (gate localMediaExtras flakeModules.nixos.containers-media-mgmt-unpackerr)
      ];
    };
}
