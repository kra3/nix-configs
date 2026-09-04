# One table, one definition per host. `flake.nix` turns this into
# `nixosConfigurations` and `darwinConfigurations` so a host's module list
# is never duplicated across those outputs.
{ inputs }:
{
  sutala = {
    class = "nixos";
    system = "x86_64-linux";
    # The Intel-iGPU overlay is applied by modules/hardware/intel-igpu.nix,
    # imported from configuration.nix itself -- it's sutala-only, not flake-wide.
    modules = [
      { nixpkgs.hostPlatform = "x86_64-linux"; }
      ../hosts/sutala/configuration.nix
    ];
  };

  mac-work = {
    class = "darwin";
    system = "aarch64-darwin";
    # No Intel overlay here: it's sutala-only (see modules/hardware/intel-igpu.nix).
    modules = [
      { nixpkgs.hostPlatform = "aarch64-darwin"; }
      inputs.home-manager.darwinModules.home-manager
      ../hosts/mac-work
    ];
  };

  surasa = {
    class = "nixos";
    system = "aarch64-linux";
    # Built via QEMU emulation on sutala, not natively -- see hosts/sutala/configuration.nix.
    # nixos-raspberrypi (not nixos-hardware): its vendor kernel is cached on cachix, avoiding
    # both nixos-hardware's uncached multi-hour compile and mainline's dwc2 USB probe hang.
    modules = [
      { nixpkgs.hostPlatform = "aarch64-linux"; }
      inputs.nixos-raspberrypi.nixosModules.raspberry-pi-3.base
      inputs.nixos-raspberrypi.nixosModules.sd-image
      inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.nixos-raspberrypi.lib.inject-overlays
      ../hosts/surasa/configuration.nix
    ];
  };
}
