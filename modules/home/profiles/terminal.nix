{
  flake.homeManagerModules.home-profiles-terminal = { ... }: {
    programs.alacritty.enable = true;
    # alacritty.toml is a read-only store symlink, so /terminal-setup can't patch it; declare
    # the Shift+Enter binding here instead.
    programs.alacritty.settings.keyboard.bindings = [
      { key = "Return"; mods = "Shift"; chars = "\n"; }
    ];
    programs.alacritty.settings.window.opacity = 0.96;
  };
}
