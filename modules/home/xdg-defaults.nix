{
  flake.homeManagerModules.home-xdg-defaults =
    { pkgs, lib, ... }:
    {
      # xdg-open has no default audio/video handler without this, so anything that
      # shells out to it (yazi's own opener bypasses this and calls mpv directly, but
      # other apps don't) silently does nothing, or in this case ends up on Picard's
      # tagger, the only other thing here claiming audio/* in mimeinfo.cache.
      # Mimetype list is derived from mpv's own .desktop entry instead of
      # hand-copied, so it can't drift out of sync.
      home.packages = [ pkgs.mpv ];
      xdg.mimeApps = {
        enable = true;
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
