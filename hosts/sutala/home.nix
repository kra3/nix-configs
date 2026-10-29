{
  config,
  lib,
  pkgs,
  osConfig,
  flakeModules,
  ...
}:
let
  publishActive = state: "${pkgs.mosquitto}/bin/mosquitto_pub -r -t sutala/active -m ${state}";
in
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
    flakeModules.homeManager.home-music-beets
    flakeModules.homeManager.home-music-lidarr-beets-retag
  ];

  programs.neovim-claudecode.enable = true;

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";
  catppuccin.accent = "blue";

  xdg.configFile."mosquitto_pub".source =
    config.lib.file.mkOutOfStoreSymlink
      osConfig.sops.templates."mosquitto_pub".path;

  services.swayidle.timeouts = [
    {
      timeout = 60;
      command = publishActive "OFF";
      resumeCommand = publishActive "ON";
    }
  ];

  home.stateVersion = lib.mkDefault "25.11";
}
