{
  flake.homeManagerModules.home-packages = { pkgs, lib, ... }: {
    home.packages =
      with pkgs;
      [
        # Display & formatting
        vivid

        # CLI utilities
        curl
        jq
        bc
        lesspipe
        glow

        # Fonts
        nerd-fonts.meslo-lg
        nerd-fonts.fira-code
        nerd-fonts.inconsolata
        smc-manjari
        smc-chilanka
        smc-meera
        smc-rachana
        smc-anjalioldlipi
        smc-karumbi
      ]
      ++ lib.optionals stdenv.isDarwin [
        switchaudio-osx # audio output switching for the sketchybar volume popup
      ];
  };
}
