{
  flake.homeManagerModules.home-gpg =
    {
      lib,
      pkgs,
      ...
    }:
    let
      isDarwin = pkgs.stdenv.isDarwin;
    in
    {
      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        defaultCacheTtl = 28800;
        maxCacheTtl = 28800;
        enableSshSupport = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        pinentry.package = lib.mkIf (!isDarwin) pkgs.pinentry-curses;
        extraConfig = lib.optionalString isDarwin ''
          pinentry-program /opt/homebrew/bin/pinentry-mac
        '';
      };
    };
}
