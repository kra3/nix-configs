{
  flake.homeManagerModules.home-gh-default = { pkgs, ... }: {
    programs.gh = {
      enable = true;
      extensions = [ pkgs.gh-dash ];
      settings = {
        git_protocol = "ssh";
        editor = "vim";
        prompt = "enabled";
        pager = "less";
        aliases = {
          co = "pr checkout";
          pv = "pr view";
          pc = "pr create";
          pl = "pr list";
          rv = "repo view";
          rc = "repo clone";
          il = "issue list";
          ic = "issue create";
          iv = "issue view";
          rl = "release list";
          d = "dash";
        };
        version = "1";
      };
    };

    # gh-dash extension config — repoPaths kept in a gitignored local file
    xdg.configFile."gh-dash/config.yml".text =
      (builtins.readFile ./gh-dash-config.yml)
      + (
        if builtins.pathExists ./gh-dash-repo-paths.yml
        then builtins.readFile ./gh-dash-repo-paths.yml
        else ""
      );
  };
}
