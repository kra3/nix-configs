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

      # Fonts
      nerd-fonts.meslo-lg
      nerd-fonts.fira-code
    ];
  };
}
