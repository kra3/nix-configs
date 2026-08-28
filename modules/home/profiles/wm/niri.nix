{
  flake.homeManagerModules.home-profiles-wm-niri = { ... }: {
    # niri-session (not bare `niri`) is what imports the environment into systemd/D-Bus.
    home.shellAliases.wm = "niri-session";

    # niri ships no default config; this is the whole session (autostart, binds, etc).
    xdg.configFile."niri/config.kdl".source = ./niri-config.kdl;
  };
}
