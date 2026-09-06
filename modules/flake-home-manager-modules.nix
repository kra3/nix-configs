{ lib, moduleLocation, ... }:
{
  options.flake.homeManagerModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
    apply = lib.mapAttrs (
      k: v: {
        _class = "homeManager";
        _file = "${toString moduleLocation}#homeManagerModules.${k}";
        imports = [ v ];
      }
    );
    description = "home-manager modules.";
  };
}
