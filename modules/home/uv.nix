{
  flake.homeManagerModules.home-uv = { pkgs, ... }: {
    home.packages = [ pkgs.uv ]; # Python installer/resolver + venv/interpreter manager
  };
}
