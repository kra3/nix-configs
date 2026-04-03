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

  config = {
    home.stateVersion = lib.mkDefault "25.11";
  };
}
