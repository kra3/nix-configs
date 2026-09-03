{ lib, flakeModules, ... }:
{
  imports = [
    flakeModules.homeManager.home-profiles-core
    flakeModules.homeManager.home-profiles-ai
    flakeModules.homeManager.home-profiles-dev
    flakeModules.homeManager.home-profiles-log-dev
    flakeModules.homeManager.home-profiles-shell
    flakeModules.homeManager.home-shell-default
    flakeModules.homeManager.home-profiles-wm-default
    flakeModules.homeManager.home-profiles-browsers
    flakeModules.homeManager.home-profiles-terminal
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";
  catppuccin.accent = "blue";

  home.stateVersion = lib.mkDefault "25.11";
}
