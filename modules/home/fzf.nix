{
  flake.homeManagerModules.home-fzf = { ... }: {
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;

      # Prefer fd: respects .gitignore, faster, hidden files by default
      defaultCommand = "fd --type f --hidden --follow --exclude .git";
      fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    };

    # catppuccin/nix fzf module has an eval error with HM 25.11 colors
    catppuccin.fzf.enable = false;
  };
}
