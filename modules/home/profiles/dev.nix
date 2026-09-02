{
  flake.homeManagerModules.home-profiles-dev = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-git-default
      flakeModules.homeManager.home-gh-default
      flakeModules.homeManager.home-uv
    ];
  };
}
