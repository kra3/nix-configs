{
  flake.homeManagerModules.home-profiles-log-dev = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-log-tools
    ];
  };
}
