{
  flake.homeManagerModules.home-fastfetch = { ... }: {
    programs.fastfetch.enable = true;
  };
}
