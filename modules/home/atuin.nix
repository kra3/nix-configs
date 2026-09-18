{
  flake.homeManagerModules.home-atuin = { ... }: {
    programs.atuin = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
