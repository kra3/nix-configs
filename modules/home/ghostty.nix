{
  flake.homeManagerModules.home-ghostty = { ... }: {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        font-family = "FiraCode Nerd Font Mono";
        font-size = 12;
        font-feature = [
          "calt"
          "liga"
          "ss01"
          "ss02"
          "ss08"
        ];
        background-opacity = 0.96;
        copy-on-select = "clipboard";
        keybind = [
          "shift+enter=text:\n"
        ];
      };
    };
  };
}
