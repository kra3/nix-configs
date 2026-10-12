{
  flake.homeManagerModules.home-uv = { pkgs, ... }: {
    home.packages = [
      pkgs.python3 # plain `python3` on PATH, e.g. for Claude Code plugin hooks
      pkgs.uv # Python installer/resolver + venv/interpreter manager
    ];
  };
}
