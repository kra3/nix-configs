{
  flake.homeManagerModules.home-profiles-terminal = { flakeModules, ... }: {
    imports = [
      flakeModules.homeManager.home-ghostty
      flakeModules.homeManager.home-yazi
    ];

    programs.alacritty.enable = true;
    # alacritty.toml is a read-only store symlink, so /terminal-setup can't patch it; declare
    # the Shift+Enter binding here instead.
    programs.alacritty.settings.keyboard.bindings = [
      {
        key = "Return";
        mods = "Shift";
        chars = "\n";
      }
    ];
    programs.alacritty.settings.window.opacity = 0.96;
    programs.alacritty.settings.selection.save_to_clipboard = true;
    programs.alacritty.settings.font.normal.family = "Inconsolata Nerd Font Mono";
    programs.alacritty.settings.font.size = 12;
  };
}
