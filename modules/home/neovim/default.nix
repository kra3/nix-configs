{
  flake.homeManagerModules.home-neovim-default =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.neovim = {
        enable = true;
        withNodeJs = false;
        withPython3 = false;
        withRuby = false;
        # Binaries land on nvim's wrapper PATH only; mason is disabled in the Lua config.
        extraPackages = [
          pkgs.basedpyright
          pkgs.lua-language-server
          pkgs.nil
          pkgs.nixfmt
          pkgs.ruff
          pkgs.statix
          pkgs.stylua
          pkgs.tree-sitter
        ]
        ++ lib.optional pkgs.stdenv.isLinux pkgs.gcc;
      };

      xdg.configFile."nvim" = {
        source = ./nvim;
        recursive = true;
      };

      # lazy-lock.json must stay writable, so it lives in the state dir; seed it from the repo once.
      home.activation.nvimLazyLock = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        lock="${config.xdg.stateHome}/nvim/lazy-lock.json"
        if [ ! -e "$lock" ] && [ -e ${./nvim/lazy-lock.json} ]; then
          install -Dm644 ${./nvim/lazy-lock.json} "$lock"
        fi
      '';
    };
}
