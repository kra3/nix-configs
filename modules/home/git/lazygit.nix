{
  flake.homeManagerModules.home-git-lazygit = { ... }: {
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
  };
}
