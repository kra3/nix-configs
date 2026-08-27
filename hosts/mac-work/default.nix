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
      flakeModules.homeManager.home-claude-code
      flakeModules.homeManager.home-mcp-nixos
      flakeModules.homeManager.home-bat
      flakeModules.homeManager.home-colordiff-default
      flakeModules.homeManager.home-eza
      flakeModules.homeManager.home-fd
      flakeModules.homeManager.home-fzf
      flakeModules.homeManager.home-gh-default
      flakeModules.homeManager.home-git-default
      flakeModules.homeManager.home-gpg
      flakeModules.homeManager.home-packages
      flakeModules.homeManager.home-ripgrep
      flakeModules.homeManager.home-sesh-default
      flakeModules.homeManager.home-shell-default
      flakeModules.homeManager.home-tmux
      flakeModules.homeManager.home-vim-default
      flakeModules.homeManager.home-zoxide
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
