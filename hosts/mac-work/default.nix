{ lib, inputs, flakeModules, ... }:
{
  # nix-darwin requires this for managed shells.
  programs.zsh.enable = true;

  # Determinate owns nix on this machine; nix-darwin must not also manage it.
  nix.enable = false;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs flakeModules; };
    sharedModules = [ inputs.catppuccin.homeModules.catppuccin ];
  };

  home-manager.users.akarunagath = {
    imports = [
      flakeModules.homeManager.home-profiles-core
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
