{
  flake.homeManagerModules.home-herdr =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      herdr = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr;

      navSrc = pkgs.fetchFromGitHub {
        owner = "paulbkim-dev";
        repo = "vim-herdr-navigation";
        rev = "v0.1.0";
        hash = "sha256-4lFrDzbdZiCIHIdkJ9q2lMlo+RCsu9eBXjK58VEuhDE=";
      };

      sidebarSrc = pkgs.fetchFromGitHub {
        owner = "testy-cool";
        repo = "herdr-sidebar-config";
        rev = "8a45adc5c0dd02f5cffeae5e900738035c9b3b82";
        hash = "sha256-YVWBjyLhDe6I9dCdCt8Bu3Ah5fVNqDF8eSsktZL0Z0c=";
      };

      shellProgress = pkgs.rustPlatform.buildRustPackage rec {
        pname = "herdr-shell-progress";
        version = "0.5.2";
        src = pkgs.fetchFromGitHub {
          owner = "bayoudhi";
          repo = "herdr-shell-progress";
          rev = "v${version}";
          hash = "sha256-40FECfvJn6w9lwp+tERZJKMNW0sMK5Ms9RrUTpxqFDU=";
        };
        cargoHash = "sha256-6DgieytxTbVrlTcccoWpRoes1qP5kfO2zaOAXxhsWA0=";
        doCheck = false;
      };

      plugins = {
        # Its claude..maki codepoints match herdr-bar's icon font, so it reuses that font instead of a second clashing one.
        # Icons default to "font": its auto check uses Nix fontconfig, which misses ~/Library/Fonts on macOS.
        "testy-cool.herdr-sidebar" = pkgs.runCommand "herdr-sidebar-plugin" { } ''
          cp -r ${sidebarSrc} $out
          chmod -R u+w $out
          substituteInPlace $out/run.sh \
            --replace-fail 'exec python3' 'PATH=${pkgs.fontconfig.bin}/bin:$PATH exec ${pkgs.python3}/bin/python3'
          substituteInPlace $out/runtime.py \
            --replace-fail 'FONT_FAMILY = "Herdr Sidebar Logos"' 'FONT_FAMILY = "Herdr Agent Icons Max"' \
            --replace-fail 'config.get("icons", "auto")' 'config.get("icons", "font")'
        '';
        # Without jq on PATH navigate.sh silently skips Vim detection.
        vim-herdr-navigation = pkgs.runCommand "vim-herdr-navigation-plugin" { } ''
          mkdir -p $out
          cp ${navSrc}/herdr-plugin.toml $out/
          install -m755 ${navSrc}/navigate.sh $out/
          substituteInPlace $out/navigate.sh \
            --replace-fail 'set -euo pipefail' 'set -euo pipefail; PATH=${pkgs.jq}/bin:$PATH'
        '';
        # `herdr plugin link` skips the manifest's [[build]] download, so bin/ comes from a Nix build.
        herdr-bar =
          let
            bin = pkgs.rustPlatform.buildRustPackage rec {
              pname = "herdr-bar";
              version = "0.14.0";
              src = pkgs.fetchFromGitHub {
                owner = "jeffarese";
                repo = "herdr-bar";
                rev = "v${version}";
                hash = "sha256-7ybX/DwOZkI7yr0U6fszlerx5/96mGO9DtLXoA4DuHs=";
              };
              cargoHash = "sha256-6aTRYRoG2bkVZiMmGWQoBEmimMUIzQGd/eeSjqboLEw=";
              doCheck = false;
            };
          in
          pkgs.runCommand "herdr-bar-plugin" { } ''
            mkdir -p $out/bin
            cp ${bin.src}/herdr-plugin.toml $out/
            ln -s ${bin}/bin/herdr-bar $out/bin/herdr-bar
          '';
        # Needs rustc 1.99.1, newer than nixpkgs; use the release binary its own installer fetches.
        "persiyanov.reviewr" =
          let
            version = "0.52.1";
            target =
              {
                x86_64-linux = {
                  triple = "x86_64-unknown-linux-musl";
                  hash = "sha256-+av+rCdF8MKT4d2gacAxk1GygEGfBbciXEjoGn/dVs0=";
                };
                aarch64-darwin = {
                  triple = "aarch64-apple-darwin";
                  hash = "sha256-bZfE10ZCCeDvzJvfqWlOkX9ZYl7j2VVsIgezawS8/7Y=";
                };
              }
              .${pkgs.stdenv.hostPlatform.system};
            src = pkgs.fetchFromGitHub {
              owner = "persiyanov";
              repo = "herdr-reviewr";
              rev = "v${version}";
              hash = "sha256-i+JtSYpEfBO9QF+UM1+TQTUvmRMQyGf1J+EKdhw0gOo=";
            };
            tarball = pkgs.fetchurl {
              url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v${version}/herdr-reviewr-${target.triple}.tar.gz";
              inherit (target) hash;
            };
          in
          pkgs.runCommand "herdr-reviewr-plugin" { } ''
            mkdir -p $out/bin
            cp ${src}/herdr-plugin.toml $out/
            tar -xzf ${tarball} -C $out/bin herdr-reviewr
          '';
        "herdr.auto-title" =
          let
            version = "0.21.0";
            bin = pkgs.buildGoModule {
              pname = "herdr-auto-title";
              inherit version;
              src = pkgs.fetchFromGitHub {
                owner = "kryptamine";
                repo = "herdr-auto-title";
                rev = "v${version}";
                hash = "sha256-uuSPjktw0CM799k+R0k2IPaiaXCCtaDVBzzBSOQkLgM=";
              };
              vendorHash = "sha256-BN/q/5o9CiklREYZloLZU2rLKUIW6Eq6Yy1Wr9vK3hU=";
              subPackages = [ "cmd/herdr-auto-title" ];
              doCheck = false;
            };
          in
          pkgs.runCommand "herdr-auto-title-plugin" { } ''
            mkdir -p $out
            cp ${bin.src}/herdr-plugin.toml $out/
            ln -s ${bin}/bin/herdr-auto-title $out/herdr-auto-title
          '';
      };

      toml = pkgs.formats.toml { };
    in
    {
      options.programs.herdr.settings = lib.mkOption {
        type = toml.type;
        default = { };
        description = "herdr config.toml contents; override per user or host.";
      };

      config = {
        home.packages = [
          herdr
          (pkgs.runCommand "herdr-agent-icons-font" { } ''
            install -Dm644 ${
              pkgs.fetchurl {
                url = "https://raw.githubusercontent.com/hhdebb/herdr-radar/v1.5.2/dist/HerdrAgentIconsMax-Regular.ttf";
                hash = "sha256-G4GZSWsiPQdh/DpJ1bJRC9o43quCyzdYvzmASVvwUnI=";
              }
            } $out/share/fonts/truetype/HerdrAgentIconsMax-Regular.ttf
          '')
        ];

        # herdr rewrites this file for onboarding and the Settings UI; those writes fail on the read-only symlink, so change it here.
        xdg.configFile."herdr/config.toml".source =
          toml.generate "herdr-config.toml" config.programs.herdr.settings;

        programs.herdr.settings = {
          onboarding = false;
          keys = {
            prefix = "ctrl+a";
            detach = "prefix+d";
            last_pane = "prefix+;";
            rename_tab = "prefix+comma";
            rename_workspace = "prefix+<";
            previous_workspace = "prefix+(";
            next_workspace = "prefix+)";
            switch_workspace = "prefix+shift+1..9";
            split_vertical = "prefix+|";
            split_horizontal = "prefix+minus";
            resize_pane_left = "prefix+shift+h";
            resize_pane_down = "prefix+shift+j";
            resize_pane_up = "prefix+shift+k";
            resize_pane_right = "prefix+shift+l";
            reload_config = "prefix+r";
            goto = "";
            clear_pane = "prefix+ctrl+l";
            resize_mode = "prefix+shift+r";
            command = [
              {
                key = "prefix+g";
                type = "plugin_action";
                command = "herdr-bar.open";
                description = "command bar";
              }
              {
                key = "prefix+alt+r";
                type = "plugin_action";
                command = "persiyanov.reviewr.toggle";
                description = "reviewr";
              }
              {
                key = "prefix+t";
                type = "plugin_action";
                command = "herdr-tsk.open-board";
                description = "tsk board";
              }
              {
                key = "prefix+a";
                type = "plugin_action";
                command = "herdr-tsk.quick-capture";
                description = "tsk quick capture";
              }
              {
                key = "ctrl+h";
                type = "plugin_action";
                command = "vim-herdr-navigation.left";
                description = "navigate left (vim/herdr)";
              }
              {
                key = "ctrl+j";
                type = "plugin_action";
                command = "vim-herdr-navigation.down";
                description = "navigate down (vim/herdr)";
              }
              {
                key = "ctrl+k";
                type = "plugin_action";
                command = "vim-herdr-navigation.up";
                description = "navigate up (vim/herdr)";
              }
              {
                key = "ctrl+l";
                type = "plugin_action";
                command = "vim-herdr-navigation.right";
                description = "navigate right (vim/herdr)";
              }
            ];
          };
          ui = {
            agent_panel_sort = "spaces";
            tab_bar_position = "bottom";
            pane_outer_borders = false;
            pane_gaps = false;
            prompt_new_tab_name = false;
            toast.delivery = "system";
            sidebar_start_collapsed = lib.mkDefault true;
            status_indicators = lib.mkDefault "symbols";
            sidebar.agents = (lib.importTOML "${sidebarSrc}/sidebar-layout.toml").ui.sidebar.agents;
            # auto-title fills $topic with the workspace's current task.
            # herdr-sidebar dims idle workspaces via $hs_space/$hs_space_dim in place of "workspace".
            sidebar.spaces.rows = [
              [
                "state_icon"
                {
                  token = "$hs_space";
                  dim = false;
                }
                {
                  token = "$hs_space_dim";
                  dim = true;
                }
                "branch"
                "git_status"
              ]
              [
                {
                  token = "$topic";
                  bold = true;
                  dim = false;
                }
              ]
            ];
          };
          experimental.pane_history = true;
        };

        # herdr rewrites its plugin registry at runtime, so link at activation; re-linking picks up new store paths.
        home.activation.herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] (
          lib.concatStrings (
            lib.mapAttrsToList (id: dir: ''
              ${herdr}/bin/herdr plugin unlink ${id} >/dev/null 2>&1 || true
              run ${herdr}/bin/herdr plugin link ${dir} --enabled
            '') plugins
          )
        );

        # Owns <C-h/j/k/l>; outside herdr it falls back to TmuxNavigate (plugins/editing.lua disables that plugin's own mappings).
        xdg.configFile."nvim/after/plugin/herdr_nav.lua".source = "${navSrc}/editor/nvim.lua";

        # Reports slow shell commands to the agents sidebar; a no-op outside herdr panes. Its cmd write lacks >|, so NO_CLOBBER breaks it.
        programs.zsh.initContent = ''
          HSP_BIN=${shellProgress}/bin/herdr-shell-progress
          source ${
            pkgs.runCommand "hsp-init.zsh" { } ''
              substitute ${shellProgress.src}/shell/init.zsh $out \
                --replace-fail '"$cmd" > "$_HSP_STATE_DIR/cmd"' '"$cmd" >| "$_HSP_STATE_DIR/cmd"'
            ''
          }
        '';

        # herdr-bar's agent logos.
        programs.ghostty.settings.font-codepoint-map = "U+E1A0-U+E1B7=Herdr Agent Icons Max";

        home.file.".claude/skills/herdr/SKILL.md".source =
          pkgs.runCommand "herdr-skill.md" { }
            "${herdr}/bin/herdr --skill > $out";
      };
    };
}
