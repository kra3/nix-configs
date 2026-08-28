{
  flake.homeManagerModules.home-profiles-wm-default = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-profiles-wm-niri
      flakeModules.homeManager.home-profiles-wm-desktop-session
    ];
    # Note: desktop-session's waybar config names niri-specific modules (modules-left: niri/workspaces, niri/window),
    # so swapping compositors would require editing this file too, not just wm/niri.nix
  };
}
