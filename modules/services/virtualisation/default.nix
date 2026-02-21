{ inputs, ... }:
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
    ./podman.nix
    ./arcane.nix
  ];
}
