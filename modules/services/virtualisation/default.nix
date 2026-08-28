{
  flake.nixosModules.services-virtualisation-default = { inputs, flakeModules, ... }: {
    imports = [
      inputs.quadlet-nix.nixosModules.quadlet
      flakeModules.nixos.services-virtualisation-podman
      flakeModules.nixos.services-virtualisation-arcane
    ];
  };
}
