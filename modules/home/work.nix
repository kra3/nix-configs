{ lib, ... }:
{
  # Work-specific additions, opt-in via import rather than a dotfiles.work
  # boolean. Both effects are additive on top of the base behaviour in
  # git/default.nix and ripgrep.nix, so mkAfter reproduces the original
  # conditional ordering exactly ([local, work] includes; base ++ work args).
  programs.git.includes = lib.mkAfter [
    { path = "~/.gitconfig.work"; }
  ];

  programs.ripgrep.arguments = lib.mkAfter [
    "--glob=!.credentials/"
    "--glob=!credentials.json"
  ];
}
