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
        ];
      };
    };
}
