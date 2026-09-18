{
  # General-purpose overlays (not hardware-specific) applied to every darwin
  # host's pkgs -- see modules/nixpkgs-overlays-nixos.nix for the NixOS side.
  flake.darwinModules.nixpkgs-overlays-darwin =
    { inputs, ... }:
    {
      nixpkgs.overlays = [
        inputs.self.overlays.nur
        inputs.self.overlays.smc-malayalam-fonts
      ];
    };
}
