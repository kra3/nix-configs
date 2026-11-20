{
  flake.nixosModules.profiles-media-video-acquire =
    { flakeModules, flakeLib, ... }:
    let
      gate = flakeLib.module-gate;
      localMedia = config: config.vars.localMedia.enable;
    in
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        (gate localMedia flakeModules.nixos.containers-media-mgmt-radarr)
        (gate localMedia flakeModules.nixos.containers-media-mgmt-sonarr)
        (gate localMedia flakeModules.nixos.containers-media-mgmt-recyclarr)
        (gate localMedia flakeModules.nixos.containers-media-mgmt-maintainerr)
        flakeModules.nixos.containers-media-mgmt-seerr
      ];
    };
}
