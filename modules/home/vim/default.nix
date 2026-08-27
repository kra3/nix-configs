{
  flake.homeManagerModules.home-vim-default = { pkgs, ... }: {
    programs.vim = {
      enable = true;
      extraConfig = builtins.readFile ./vimrc;
    };

    home.file = {
      ".vim/autoload/plug.vim".source = "${pkgs.vimPlugins.vim-plug}/plug.vim";
      ".gvimrc".source = ./gvimrc;
      ".ideavimrc".source = ./ideavimrc;
    };
  };
}
