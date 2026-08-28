{
  flake.nixosModules.services-surveillance-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.services-surveillance-nvr
    ];
  };
}
