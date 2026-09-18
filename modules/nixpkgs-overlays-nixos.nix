{
  # General-purpose overlays (not hardware-specific) applied to every NixOS
  # host's pkgs -- deliberately excludes intel-media-sdk-cxx17, which
  # hardware-intel-igpu.nix applies on its own, sutala-only.
  flake.nixosModules.nixpkgs-overlays-nixos =
    { inputs, ... }:
    {
      nixpkgs.overlays = [
        inputs.self.overlays.nur
        inputs.self.overlays.smc-malayalam-fonts
      ];
    };
}
