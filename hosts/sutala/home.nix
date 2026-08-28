{ lib, flakeModules, ... }:
{
  imports = [
    flakeModules.homeManager.home-profiles-core
    flakeModules.homeManager.home-profiles-ai
    flakeModules.homeManager.home-profiles-dev
    flakeModules.homeManager.home-profiles-shell
    flakeModules.homeManager.home-shell-default
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";
  catppuccin.accent = "blue";

  home.stateVersion = lib.mkDefault "25.11";
}
