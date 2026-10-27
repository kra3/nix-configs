{
  flake.homeManagerModules.home-gh-default =
    { inputs, pkgs, ... }:
    let
      gh-stack = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.gh-stack;
    in
    {
      home.file.".claude/skills/gh-stack".source = "${gh-stack.src}/skills/gh-stack";

      programs.gh = {
        enable = true;
        extensions = [
          pkgs.gh-dash
          pkgs.gh-f
          gh-stack
        ];
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
          if builtins.pathExists ./gh-dash-repo-paths.yml then
            builtins.readFile ./gh-dash-repo-paths.yml
          else
            ""
        );
    };
}
