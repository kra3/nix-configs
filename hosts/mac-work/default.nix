{ lib, inputs, ... }:
{
  # nix-darwin system settings
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # System-level shell setup (nix-darwin requires this for managed shells)
  programs.zsh.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs; };
    sharedModules = [ inputs.catppuccin.homeModules.catppuccin ];
  };

  home-manager.users.akarunagath = {
    imports = [ ../../modules/home ];

    home.username = "akarunagath";
    home.homeDirectory = lib.mkForce "/Users/akarunagath";

    dotfiles = {
      desktop = false;
      work = true;
      githubUser = "kra3";
    };
  };

  system.stateVersion = 6;
}
