{ lib, ... }:
{
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Shared helper-function libraries, consumed via the flakeLib specialArgs bundle.";
  };
}
