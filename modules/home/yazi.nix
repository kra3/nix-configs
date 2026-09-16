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
        # default "play" opener shells out to xdg-open; call mpv directly instead.
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
