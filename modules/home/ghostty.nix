{
  flake.homeManagerModules.home-ghostty = { ... }: {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      settings = {
        font-family = "FiraCode Nerd Font Mono";
        font-size = 11;
        font-feature = [
          "calt"
          "liga"
          "ss01"
          "ss02"
          "ss08"
        ];
        background-opacity = 0.96;
        copy-on-select = "clipboard";
        macos-option-as-alt = true;
        macos-titlebar-style = "hidden";
        keybind = [
          "shift+enter=text:\n"
        ];
      };
    };
  };
}
