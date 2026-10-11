{
  flake.homeManagerModules.home-herdr = { inputs, pkgs, ... }: {
    home.packages = [ inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr ];
  };
}
