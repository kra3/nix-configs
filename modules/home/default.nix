{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./claude-code.nix
    ./mcp-nixos.nix
    ./bat.nix
    ./colordiff
    ./eza.nix
    ./fd.nix
    ./fzf.nix
    ./gh
    ./git
    ./gpg.nix
    ./packages.nix
    ./ripgrep.nix
    ./sesh
    ./shell
    ./tmux.nix
    ./vim
    ./zoxide.nix
  ];

  config = {
    catppuccin.enable = true;
    catppuccin.flavor = "mocha";
    catppuccin.accent = "blue";

    home.stateVersion = lib.mkDefault "25.11";
  };
}
