# One table, one definition per host. `flake.nix` turns this into
# `nixosConfigurations`, `darwinConfigurations` and `colmena` so a host's
# module list is never duplicated across those three outputs.
{ inputs }:
{
  sutala = rec {
    class = "nixos";
    system = "x86_64-linux";
    # The host's actual feature config, written once and reused verbatim by
    # both `modules` below (nixosConfigurations) and colmena (flake.nix),
    # which imports this same path directly instead of a second copy.
    # The Intel-iGPU overlay is applied by modules/hardware/intel-igpu.nix,
    # imported from configModule itself -- it's sutala-only, not flake-wide.
    configModule = ../hosts/sutala/configuration.nix;
    modules = [
      { nixpkgs.hostPlatform = "x86_64-linux"; }
      configModule
    ];
    # colmena-only deployment metadata.
    deployment = {
      targetHost = "sutala-root";
      targetUser = "root";
      buildOnTarget = true;
    };
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
}
