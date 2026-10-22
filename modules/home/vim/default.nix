{
  flake.homeManagerModules.home-vim-default =
    { ... }:
    {
      programs.vim = {
        enable = true;
        extraConfig = builtins.readFile ./vimrc;
      };

      home.file = {
        ".gvimrc".source = ./gvimrc;
        ".ideavimrc".source = ./ideavimrc;
      };
    };
}
