{
  pkgs,
  ...
}:
let
  baseConfig = ''
    # Sesh Configuration
    # https://github.com/joshmedeski/sesh

    default_session_dir = "~"
  '';

  iconConfig = ''

    [icons]
    default = "📁"
    git = "󰊢"
    home = "󰋜"
    config = ""
    downloads = "󰇚"
    documents = "󰈙"
    zoxide = ""
    tmux = ""
    session = ""
  '';
in
{
  home.packages = [ pkgs.sesh ];

  # session_paths kept in a gitignored local file
  xdg.configFile."sesh/sesh.toml".text =
    baseConfig
    + (
      if builtins.pathExists ./sesh-session-paths.toml
      then builtins.readFile ./sesh-session-paths.toml
      else ""
    )
    + iconConfig;
}
