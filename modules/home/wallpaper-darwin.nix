{
  # macOS desktop wallpaper. nix-darwin has no option for it, and osascript
  # (System Events / Finder) is blocked by TCC/Automation from a headless
  # `darwin-rebuild switch`. desktoppr uses NSWorkspace.setDesktopImageURL —
  # no TCC prompt — so it works from activation. Reuses the Linux wallpaper.
  flake.homeManagerModules.home-wallpaper-darwin =
    { pkgs, lib, ... }:
    {
      home.packages = [ pkgs.desktoppr ];
      home.activation.wallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.desktoppr}/bin/desktoppr ${./profiles/wm/wallpapers/wallpaper.png}
      '';
    };
}
