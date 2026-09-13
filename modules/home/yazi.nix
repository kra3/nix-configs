{
  flake.homeManagerModules.home-yazi =
    { pkgs, ... }:
    {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        enableBashIntegration = true;
        extraPackages = with pkgs; [
          ffmpegthumbnailer
          poppler
          imagemagick
        ];
      };
    };
}
