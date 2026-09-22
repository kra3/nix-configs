{
  flake.homeManagerModules.home-packages = { pkgs, ... }: {
    home.packages = with pkgs; [
      # Display & formatting
      vivid

      # CLI utilities
      curl
      jq
      bc
      lesspipe
      glow
      switchaudio-osx # audio output switching for the sketchybar volume popup

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
    ];
  };
}
