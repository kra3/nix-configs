{
  flake.homeManagerModules.home-profiles-core = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-vim-default
      flakeModules.homeManager.home-tmux
      flakeModules.homeManager.home-gpg
      flakeModules.homeManager.home-packages
      flakeModules.homeManager.home-sesh-default
    ];
  };
}
