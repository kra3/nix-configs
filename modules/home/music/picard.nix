{
  flake.homeManagerModules.home-music-picard = { pkgs, ... }: {
    home.packages = [ pkgs.picard ];
  };
}
