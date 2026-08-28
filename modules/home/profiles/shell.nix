{
  flake.homeManagerModules.home-profiles-shell = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-bat
      flakeModules.homeManager.home-colordiff-default
      flakeModules.homeManager.home-eza
      flakeModules.homeManager.home-fd
      flakeModules.homeManager.home-fzf
      flakeModules.homeManager.home-ripgrep
      flakeModules.homeManager.home-zoxide
    ];
  };
}
