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
    configModule = ../hosts/sutala/configuration.nix;
    modules = [
      { nixpkgs.hostPlatform = "x86_64-linux"; }
      { nixpkgs.overlays = [ inputs.self.overlays.default ]; }
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
    modules = [
      { nixpkgs.hostPlatform = "aarch64-darwin"; }
      { nixpkgs.overlays = [ inputs.self.overlays.default ]; }
      inputs.home-manager.darwinModules.home-manager
      ../hosts/mac-work
    ];
  };
}
