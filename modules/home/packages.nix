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

      # Fonts
      nerd-fonts.meslo-lg
      nerd-fonts.fira-code
    ];
  };
}
