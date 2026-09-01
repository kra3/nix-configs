{
  flake.homeManagerModules.home-vim-default = { pkgs, lib, ... }: {
    programs.vim = {
      enable = true;
      extraConfig = builtins.readFile ./vimrc;
    };

    home.file = {
      ".vim/autoload/plug.vim".source = "${pkgs.vimPlugins.vim-plug}/plug.vim";
      ".gvimrc".source = ./gvimrc;
      ".ideavimrc".source = ./ideavimrc;

      # programs.vim bakes ./vimrc into the nix vim package but doesn't write
      # ~/.vimrc. On darwin, vim is used via Homebrew (aliased in ~/.shell_local
      # for vim-ai's python3), which reads ~/.vimrc — so manage it there. Same
      # ./vimrc content. Darwin-only: on Linux the nix vim uses the baked config,
      # and adding ~/.vimrc would double-load it.
      ".vimrc" = lib.mkIf pkgs.stdenv.isDarwin { source = ./vimrc; };
    };
  };
}
