{ lib, inputs, flakeModules, ... }:
{
  imports = [
    flakeModules.darwin.services-system-nix-defaults-darwin
  ];

  # System-level shell setup (nix-darwin requires this for managed shells)
  programs.zsh.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs flakeModules; };
    sharedModules = [ inputs.catppuccin.homeModules.catppuccin ];
  };

  home-manager.users.akarunagath = {
    imports = [
      flakeModules.homeManager.home-profiles-core
      flakeModules.homeManager.home-profiles-ai
      flakeModules.homeManager.home-profiles-dev
      flakeModules.homeManager.home-profiles-shell
      flakeModules.homeManager.home-shell-default
      flakeModules.homeManager.home-work
    ];

    home.username = "akarunagath";
    home.homeDirectory = lib.mkForce "/Users/akarunagath";

    catppuccin.enable = true;
    catppuccin.flavor = "mocha";
    catppuccin.accent = "blue";

    home.stateVersion = lib.mkDefault "25.11";
  };

  system.stateVersion = 6;
}
