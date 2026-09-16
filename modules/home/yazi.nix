{
  flake.homeManagerModules.home-yazi =
    { pkgs, ... }:
    {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        enableBashIntegration = true;
        shellWrapperName = "y";
        extraPackages = with pkgs; [
          ffmpegthumbnailer
          poppler
          imagemagick
          mpv
        ];
        # yazi's default "play" opener shells out to xdg-open, which has no
        # registered handler here; call mpv directly instead.
        settings.opener.play = [
          {
            run = ''mpv "$@"'';
            orphan = true;
            for = "unix";
          }
        ];
      };
    };
}
