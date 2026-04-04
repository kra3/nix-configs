{ ... }:
{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  # catppuccin/nix fzf module has an eval error with HM 25.11 colors
  catppuccin.fzf.enable = false;
}
