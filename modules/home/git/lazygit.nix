{
  flake.homeManagerModules.home-git-lazygit = { config, lib, pkgs, ... }: {
    programs.lazygit = {
      enable = true;
      settings = {
        screenMode = "normal";

        gui = {
          scrollHeight = 2;
          scrollPastBottom = true;
          sidePanelWidth = 0.3333;
          expandFocusedSidePanel = false;
          mainPanelSplitMode = "flexible";

          showListFooter = true;
          showFileTree = true;
          showRandomTip = false;
          showBranchCommitHash = true;
          showBottomLine = false;
          showCommandLog = false;
          showIcons = true;

          commitLength.show = true;
          mouseEvents = true;
          skipDiscardChangeWarning = false;
          skipStashWarning = false;
          skipNoStagedFilesWarning = false;
          skipRewordInEditorWarning = false;

          border = "rounded";

          # Catppuccin Mocha (blue accent). catppuccin/nix ships lazygit theme
          # files (catppuccin-lazygit) but release-25.11 does NOT wire them into
          # programs.lazygit, so catppuccin.<x>.enable is a no-op for lazygit.
          # Embed catppuccin's own mocha/blue values (matches both hosts'
          # accent = blue). Update these if catppuccin.accent changes, or drop
          # in favour of catppuccin.lazygit.enable once upstream wires it.
          theme = {
            activeBorderColor = [ "#89b4fa" "bold" ];
            inactiveBorderColor = [ "#a6adc8" ];
            optionsTextColor = [ "#89b4fa" ];
            selectedLineBgColor = [ "#313244" ];
            cherryPickedCommitBgColor = [ "#45475a" ];
            cherryPickedCommitFgColor = [ "#89b4fa" ];
            unstagedChangesColor = [ "#f38ba8" ];
            defaultFgColor = [ "#cdd6f4" ];
            searchingActiveBorderColor = [ "#f9e2af" ];
          };
          authorColors = { "*" = "#b4befe"; };
        };

        git = {
          pagers = [
            {
              colorArg = "always";
              pager = "delta --dark --paging=never";
            }
          ];
          commit = {
            signOff = false;
            autoWrapCommitMessage = true;
            autoWrapWidth = 72;
          };
          merging = {
            manualCommit = false;
            args = "";
          };
          log = {
            order = "topo-order";
            showGraph = "when-maximised";
            showWholeGraph = false;
          };
          skipHookPrefix = "WIP";
          autoFetch = true;
          autoRefresh = true;
          branchLogCmd = "git log --graph --color=always --abbrev-commit --decorate --date=relative --pretty=medium {{branchName}} --";
          allBranchesLogCmds = [
            "git log --graph --all --color=always --abbrev-commit --decorate --date=relative --pretty=medium"
          ];
          overrideGpg = true;
          disableForcePushing = false;
          parseEmoji = false;
          pull.mode = "merge";
        };

        os = {
          editCommand = "";
          editCommandTemplate = "{{editor}} {{filename}}";
          openCommand = "";
          openLinkCommand = "";
        };

        update.method = "never";

        refresher = {
          refreshInterval = 10;
          fetchInterval = 60;
        };

        confirmOnQuit = false;
        disableStartupPopups = true;

        customCommands = [
          {
            key = "<c-a>";
            context = "files";
            command = "git add -A";
            description = "Stage all files";
            output = "terminal";
          }
          {
            key = "C";
            context = "global";
            command = "git commit";
            description = "Commit with editor";
            output = "terminal";
          }
          {
            key = "P";
            context = "global";
            command = "git push";
            description = "Push to remote";
            loadingText = "Pushing...";
            output = "terminal";
          }
        ];

        notARepository = "prompt";
      };
    };

    # Darwin: home-manager writes lazygit's config to
    # ~/Library/Application Support/lazygit/config.yml, but with XDG_CONFIG_HOME
    # set (see modules/home/shell/common/default.nix) lazygit reads
    # ~/.config/lazygit/config.yml instead. Mirror the generated (themed) config
    # to the XDG path so it's actually used. Linux writes to ~/.config/lazygit
    # directly, so no mirror is needed (and the Library path doesn't exist there).
    home.file.".config/lazygit/config.yml" = lib.mkIf pkgs.stdenv.isDarwin {
      source = config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/Library/Application Support/lazygit/config.yml";
    };
  };
}
