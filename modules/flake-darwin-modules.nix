{ lib, moduleLocation, ... }:
{
  options.flake.darwinModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
    apply = lib.mapAttrs (k: v: {
      _class = "darwin";
      _file = "${toString moduleLocation}#darwinModules.${k}";
      imports = [ v ];
    });
    description = "nix-darwin modules.";
  };
}
