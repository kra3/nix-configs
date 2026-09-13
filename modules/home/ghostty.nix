{
  flake.homeManagerModules.home-ghostty = { ... }: {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        font-family = "Inconsolata Nerd Font Mono";
        font-size = 12;
        background-opacity = 0.96;
      };
    };
  };
}
