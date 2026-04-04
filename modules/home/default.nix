{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.dotfiles;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  options.dotfiles = {
    desktop = lib.mkEnableOption "Linux desktop tools (i3, conky, etc.)";
    work = lib.mkEnableOption "work-specific settings";

    githubUser = lib.mkOption {
      type = lib.types.str;
      default = "kra3";
      description = "GitHub username";
    };
  };

  imports = [
    ./bat.nix
    ./colordiff
    ./fd.nix
    ./ripgrep.nix
  ];

  config = {
    catppuccin.enable = true;
    catppuccin.flavor = "mocha";
    catppuccin.accent = "blue";

    home.stateVersion = lib.mkDefault "25.11";
  };
}
