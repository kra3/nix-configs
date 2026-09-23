{
  flake.homeManagerModules.home-vim-default = { pkgs, ... }: {
    programs.vim = {
      enable = true;
      extraConfig = builtins.readFile ./vimrc;
    };

    # Python tooling the vimrc's LSP/ALE config expects on PATH:
    # basedpyright (LSP: types/nav) + ruff (ALE: lint + format).
    home.packages = [
      pkgs.basedpyright
      pkgs.ruff
    ];

    home.file = {
      ".vim/autoload/plug.vim".source = "${pkgs.vimPlugins.vim-plug}/plug.vim";
      ".gvimrc".source = ./gvimrc;
      ".ideavimrc".source = ./ideavimrc;
    };
  };
}
