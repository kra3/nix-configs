{
  flake.homeManagerModules.home-ghostty = { pkgs, ... }: {
    programs.ghostty = {
      enable = true;
      # nixpkgs' ghostty isn't built for darwin; ghostty-bin is the prebuilt binary that works there.
      package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
      enableZshIntegration = true;
      enableBashIntegration = true;
      settings = {
        font-family = "FiraCode Nerd Font Mono";
        # macOS renders at a larger effective size on retina displays than Linux at the same point size.
        font-size = if pkgs.stdenv.isDarwin then 13 else 11;
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
