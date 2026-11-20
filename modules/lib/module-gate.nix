{ lib, ... }:
{
  # Defers a module (and its nested imports) behind a config condition.
  flake.lib.module-gate =
    let
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
    in
    gate;
}
