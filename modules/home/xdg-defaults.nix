{
  flake.homeManagerModules.home-xdg-defaults =
    { pkgs, lib, ... }:
    {
      # mpv as xdg-open default for audio/video; without this it fell through to Picard's tagger.
      home.packages = [ pkgs.mpv ];
      xdg.mimeApps = {
        enable = true;
        # derive mimetypes from mpv's own .desktop entry rather than hand-copying them
        defaultApplications = lib.genAttrs (lib.pipe "${pkgs.mpv}/share/applications/mpv.desktop" [
          builtins.readFile
          (lib.splitString "\n")
          (builtins.filter (lib.hasPrefix "MimeType="))
          lib.head
          (lib.removePrefix "MimeType=")
          (lib.splitString ";")
          (builtins.filter (s: s != ""))
        ]) (_: "mpv.desktop");
      };
    };
}
