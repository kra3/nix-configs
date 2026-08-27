{
  flake.homeManagerModules.home-zoxide = { ... }: {
    programs.zoxide = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
    };
  };
}
