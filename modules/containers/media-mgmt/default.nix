{
  flake.nixosModules.containers-media-mgmt-default =
    {
      flakeModules,
      lib,
      ...
    }:
    let
      # Defers a module (and its nested imports) behind a config condition.
      gate =
        cond: module:
        {
          config,
          pkgs,
          ...
        }@args:
        let
          m = if lib.isFunction module then module args else module;
        in
        {
          imports = map (gate cond) (m.imports or [ ]);
          config = lib.mkIf (cond config) (
            removeAttrs m [
              "imports"
              "_class"
              "_file"
            ]
          );
        };

      localMedia = config: config.vars.localMedia.enable;
      localMediaExtras = config: config.vars.localMedia.enable && config.vars.localMedia.extras.enable;
    in
    {
      imports = [
        flakeModules.nixos.containers-media-mgmt-network
        flakeModules.nixos.containers-media-mgmt-storage
        # services
        (gate localMedia flakeModules.nixos.containers-media-mgmt-radarr)
        (gate localMedia flakeModules.nixos.containers-media-mgmt-sonarr)
        flakeModules.nixos.containers-media-mgmt-prowlarr
        flakeModules.nixos.containers-media-mgmt-sabnzbd
        (gate localMediaExtras flakeModules.nixos.containers-media-mgmt-bazarr)
        flakeModules.nixos.containers-media-mgmt-lidarr
        flakeModules.nixos.containers-media-mgmt-bookshelf
        flakeModules.nixos.containers-media-mgmt-audiobookshelf
        flakeModules.nixos.containers-media-mgmt-seerr
        (gate localMedia flakeModules.nixos.containers-media-mgmt-recyclarr)
        (gate localMediaExtras flakeModules.nixos.containers-media-mgmt-unpackerr)
        (gate localMedia flakeModules.nixos.containers-media-mgmt-maintainerr)
        flakeModules.nixos.containers-media-mgmt-aiostreams
        flakeModules.nixos.containers-media-mgmt-aiometadata
        flakeModules.nixos.containers-media-mgmt-slskd
      ];
    };
}
