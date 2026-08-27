{
  flake.homeManagerModules.home-eza = { ... }: {
    programs.eza = {
      enable = true;
      icons = "auto";
      git = true;
    };
  };
}
