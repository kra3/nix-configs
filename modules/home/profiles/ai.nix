{
  flake.homeManagerModules.home-profiles-ai = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-claude-code
      flakeModules.homeManager.home-mcp-nixos
    ];
  };
}
