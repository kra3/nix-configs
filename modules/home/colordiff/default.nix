{
  flake.homeManagerModules.home-colordiff-default = { pkgs, ... }: {
    home.packages = [ pkgs.colordiff ];
    home.file.".colordiffrc".source = ./colordiffrc;
  };
}
