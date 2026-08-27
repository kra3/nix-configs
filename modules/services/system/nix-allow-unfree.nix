{
  flake.nixosModules.services-system-nix-allow-unfree = {
    nixpkgs.config.allowUnfree = true;
  };
}
