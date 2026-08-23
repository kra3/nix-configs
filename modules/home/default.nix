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
    desktop = lib.mkEnableOption "desktop-specific settings";
    work = lib.mkEnableOption "work-specific settings";

    githubUser = lib.mkOption {
      type = lib.types.str;
      default = "kra3";
      description = "GitHub username";
    };
  };

  imports = [
    ./claude-code.nix
    ./bat.nix
    ./colordiff
    ./eza.nix
    ./fd.nix
    ./fzf.nix
    ./gh
    ./git
    ./gpg.nix
    ./packages.nix
    ./ripgrep.nix
    ./sesh
    ./shell
    ./tmux.nix
    ./vim
    ./zoxide.nix
  ];

  config = {
    catppuccin.enable = true;
    catppuccin.flavor = "mocha";
    catppuccin.accent = "blue";

    home.stateVersion = lib.mkDefault "25.11";
  };
}
