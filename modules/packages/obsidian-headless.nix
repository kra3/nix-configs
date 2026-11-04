{ inputs, ... }:
{
  perSystem =
    { lib, system, ... }:
    let
      # Unfree (Obsidian EULA) and only on unstable; allowed for this one package.
      unstable = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate = drv: lib.getName drv == "obsidian-headless";
      };
    in
    {
      # Used by services-second-brain-default and `just second-brain-secrets` (`ob login`).
      packages =
        lib.optionalAttrs (lib.meta.availableOn unstable.stdenv.hostPlatform unstable.obsidian-headless)
          {
            inherit (unstable) obsidian-headless;
          };
    };
}
