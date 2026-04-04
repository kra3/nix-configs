{ pkgs, ... }:
{
  home.packages = [ pkgs.colordiff ];
  home.file.".colordiffrc".source = ./colordiffrc;
}
