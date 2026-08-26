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
    imports = [
      ../../modules/home
      ../../modules/home/work.nix
    ];

    home.username = "akarunagath";
    home.homeDirectory = lib.mkForce "/Users/akarunagath";
  };

  system.stateVersion = 6;
}
