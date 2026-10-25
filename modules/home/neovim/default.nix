{
  flake.homeManagerModules.home-neovim-default =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.neovim-langs;
      codelldb = pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter;
      javaDebug = "${pkgs.vscode-extensions.vscjava.vscode-java-debug}/share/vscode/extensions/vscjava.vscode-java-debug/server";
      javaTest = "${pkgs.vscode-extensions.vscjava.vscode-java-test}/share/vscode/extensions/vscjava.vscode-java-test/server";

      # Per language: Nix packages, LazyVim extras to import, and debug tools check-tools should expect.
      languages = {
        nix = {
          default = true;
          packages = [
            pkgs.nixd
            pkgs.nixfmt
            pkgs.statix
          ];
          extras = [ "lang.nix" ];
        };
        lua = {
          default = true;
          packages = [
            pkgs.lua-language-server
            pkgs.stylua
          ];
          extras = [ ];
        };
        python = {
          default = true;
          packages = [
            pkgs.basedpyright
            pkgs.python3Packages.debugpy
            pkgs.ruff
          ];
          extras = [ "lang.python" ];
        };
        typescript = {
          default = false;
          packages = [
            pkgs.biome
            pkgs.vtsls
            (pkgs.writeShellScriptBin "js-debug-adapter" "exec ${lib.getExe pkgs.vscode-js-debug} \"$@\"")
          ];
          extras = [
            "lang.typescript"
            "lang.typescript.biome"
          ];
          tools = [ "js-debug-adapter" ];
        };
        scala = {
          default = false;
          packages = [
            pkgs.bloop
            pkgs.metals
            pkgs.temurin-bin-21
          ];
          extras = [ "lang.scala" ];
        };
        java = {
          default = false;
          packages = [
            pkgs.jdt-language-server
            pkgs.temurin-bin-21
          ];
          extras = [ "lang.java" ];
          bundles = [
            "${javaDebug}/com.microsoft.java.debug.plugin-*.jar"
            "${javaTest}/*.jar"
          ];
        };
        rust = {
          default = false;
          packages = [
            pkgs.rust-analyzer
            codelldb
          ];
          extras = [ "lang.rust" ];
          tools = [ "codelldb" ];
        };
        go = {
          default = false;
          packages = [
            pkgs.delve
            pkgs.gofumpt
            pkgs.golangci-lint
            pkgs.gomodifytags
            pkgs.gopls
            pkgs.gotools
            pkgs.impl
          ];
          extras = [ "lang.go" ];
          tools = [ "dlv" ];
        };
        cpp = {
          default = false;
          packages = [
            pkgs.clang-tools
            codelldb
          ];
          extras = [ "lang.clangd" ];
          tools = [ "codelldb" ];
        };
      };

      enabled = lib.filterAttrs (name: _: cfg.${name}.enable) languages;
      perLang = field: lib.concatMap (l: l.${field} or [ ]) (lib.attrValues enabled);
    in
    {
      options.programs.neovim-langs = lib.mapAttrs (name: l: {
        enable = lib.mkEnableOption "${name} support in Neovim" // {
          default = l.default;
        };
      }) languages;

      config = {
        programs.neovim = {
          enable = true;
          withNodeJs = false;
          withPython3 = false;
          withRuby = false;
          # Binaries land on nvim's wrapper PATH only; mason is disabled in the Lua config.
          extraPackages = [
            pkgs.ghostscript
            pkgs.imagemagick
            pkgs.shfmt
            pkgs.tree-sitter
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [
            pkgs.gcc
            pkgs.trash-cli
          ]
          ++ lib.unique (perLang "packages");
        };

        xdg.configFile."nvim" = {
          source = lib.cleanSourceWith {
            src = ./nvim;
            filter = path: _: baseNameOf path != "lazy-lock.json";
          };
          recursive = true;
        };

        # Read by lua/config/lazy.lua, plugins/* and check-tools.lua.
        xdg.configFile."nvim/lua/config/nix-langs.lua".text = ''
          return ${
            lib.generators.toLua { } {
              langs =
                lib.mapAttrs (_: _: true) enabled
                // lib.mapAttrs (_: _: false) (lib.removeAttrs languages (lib.attrNames enabled));
              extras = lib.unique (perLang "extras");
              tools = lib.unique (perLang "tools");
              bundles = perLang "bundles";
            }
          }
        '';

        # lazy-lock.json must stay writable, so it lives in the state dir; seed it, then add repo pins it lacks.
        home.activation.nvimLazyLock = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          lock="${config.xdg.stateHome}/nvim/lazy-lock.json"
          if [ ! -e "$lock" ]; then
            run install -Dm644 ${./nvim/lazy-lock.json} "$lock"
          else
            merged="$(${lib.getExe pkgs.jq} -s '.[0] * .[1]' ${./nvim/lazy-lock.json} "$lock")" && \
              run sh -c 'printf "%s\n" "$1" > "$2"' _ "$merged" "$lock"
          fi
        '';
      };
    };
}
