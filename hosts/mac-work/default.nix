{ lib, inputs, ... }:
{
  imports = [
    ../../modules/services/system/nix-defaults-darwin.nix
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
      ../../modules/home/claude-code.nix
      ../../modules/home/mcp-nixos.nix
      ../../modules/home/bat.nix
      ../../modules/home/colordiff
      ../../modules/home/eza.nix
      ../../modules/home/fd.nix
      ../../modules/home/fzf.nix
      ../../modules/home/gh
      ../../modules/home/git
      ../../modules/home/gpg.nix
      ../../modules/home/packages.nix
      ../../modules/home/ripgrep.nix
      ../../modules/home/sesh
      ../../modules/home/shell
      ../../modules/home/tmux.nix
      ../../modules/home/vim
      ../../modules/home/zoxide.nix
      ../../modules/home/work.nix
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
