{
  flake.homeManagerModules.home-profiles-wm-default = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-profiles-wm-niri
      flakeModules.homeManager.home-profiles-wm-desktop-session
    ];
  };
}
