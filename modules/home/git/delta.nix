{
  flake.homeManagerModules.home-git-delta = { lib, ... }: {
    programs.delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        light = false;
        line-numbers = true;
        side-by-side = false;
        syntax-theme = "Monokai Extended";
        # catppuccin sets features = "catppuccin-mocha"; combine both
        features = lib.mkForce "catppuccin-mocha decorations";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
          file-decoration-style = "none";
          hunk-header-decoration-style = "cyan box ul";
        };
      };
    };
  };
}
