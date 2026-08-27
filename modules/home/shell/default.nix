{
  flake.homeManagerModules.home-shell-default = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-shell-bash-default
      flakeModules.homeManager.home-shell-common-default
      flakeModules.homeManager.home-shell-readline
      flakeModules.homeManager.home-shell-zsh-default
    ];
  };
}
