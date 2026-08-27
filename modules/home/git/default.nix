{
  flake.homeManagerModules.home-git-default =
    {
      lib,
      pkgs,
      flakeModules,
      ...
    }:
    {
      imports = [
        flakeModules.homeManager.home-git-delta
        flakeModules.homeManager.home-git-lazygit
      ];

      home.packages = with pkgs; [
        git-absorb
        difftastic
      ];

      programs.git = {
        enable = true;

        ignores = builtins.filter (s: s != "" && !(lib.hasPrefix "#" s))
          (lib.splitString "\n" (builtins.readFile ./gitignore_global));

        includes = [
          { path = "~/.gitconfig.local"; }
        ];

        settings = {
          # user.name and user.email are NOT set here — they are provided by
          # ~/.gitconfig.local (personal) or ~/.gitconfig.work (work), which are
          # included above.  This keeps personal/work email addresses out of the
          # public repo.  See docs/setup.md for first-time setup instructions.
          alias = {
            tags = "tag -l";

            b = "branch";
            ba = "branch -a";
            branches = "branch -a";
            currentbranch = "!git symbolic-ref --short HEAD";

            r = "remote -v";
            remotes = "remote -v";
            fu = "fetch upstream";

            cleanup = "!git branch --merged | grep -v '\\\\*\\\\|main\\\\|master\\\\|develop' | xargs -n 1 git branch -d";
            gone = "!git fetch -p && git for-each-ref --format '%(refname:short) %(upstream:track)' | awk '$2 == \"[gone]\" {print $1}' | xargs -r git branch -D";

            wl = "worktree list";
            wp = "worktree prune";

            ll = "log --pretty=oneline --abbrev-commit --graph";
            l = "log --oneline --graph -10";
            lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";

            st = "status -sb";

            ci = "commit";
            amend = "commit --amend";
            wip = "!git add . && git commit -n -m \"WIP\"";

            co = "checkout";
            sw = "switch";
            swc = "switch -c";
            restore = "restore";
            coo = ''!git branch --sort=-committerdate --no-color --format="%(refname:short)" | fzf | xargs git checkout'';
            cm = "checkout main";
            nb = "checkout -b";

            df = "diff";
            dc = "diff --cached";
            ds = "diff --staged";
            dw = "diff --word-diff";
            dl = "diff HEAD~1";
            dft = "difftool --tool=difftastic";
            changes = "diff --name-status";
            branch-files = "!git diff --name-only main...HEAD";
            patch = "!git --no-pager diff --no-color";

            a = "add";
            aa = "add --all";
            ap = "add --patch";

            undo = "reset --soft HEAD^";
            unstage = "reset HEAD";

            sl = "stash list";
            sp = "stash pop";
            ss = "stash save";
            sa = "stash apply";

            cp = "cherry-pick";

            fixup = "!git log -n 50 --pretty=format:'%h %s' --no-merges | fzf | cut -c -7 | xargs -o git commit --fixup";
            absorb = "!git-absorb --and-rebase";

            publish = "!git push -u origin $(git currentbranch)";
            unpublish = "!git push origin :$(git currentbranch)";

            copr = "!sh -c 'git fetch upstream refs/pull/\${1}/head && git checkout FETCH_HEAD' -";

            ctags = "!.git/hooks/ctags";
            gh = "!f() { git clone https://github.com/$1; }; f";
          };

          init.defaultBranch = "main";

          core.ignorecase = false;

          push = {
            default = "current";
            autoSetupRemote = true;
          };

          pull.rebase = true;

          fetch = {
            prune = true;
            prunetags = true;
          };

          rebase = {
            autoStash = true;
            autoSquash = true;
          };

          branch.sort = "-committerdate";

          column = {
            ui = "auto";
            branch = "auto";
            tag = "auto";
          };

          log.date = "relative";

          color = {
            ui = true;
            branch = {
              current = "yellow reverse";
              local = "yellow";
              remote = "green";
            };
            diff = {
              meta = "227";
              frag = "magenta bold";
              old = "red bold";
              new = "green bold";
              commit = "227 bold";
              whitespace = "red reverse";
            };
            status = {
              added = "yellow";
              changed = "green";
              untracked = "cyan";
            };
            diff-highlight = {
              oldNormal = "red bold";
              oldHighlight = "red bold 52";
              newNormal = "green bold";
              newHighlight = "green bold 22";
            };
          };

          merge = {
            conflictstyle = "diff3";
            tool = "vimdiff";
            prompt = false;
          };

          difftool = {
            prompt = false;
            difftastic.cmd = ''difft "$LOCAL" "$REMOTE"'';
          };

          rerere.enabled = true;

          "credential \"https://github.com\"" = {
            helper = [
              ""
              "!gh auth git-credential"
            ];
          };

          "credential \"https://gist.github.com\"" = {
            helper = [
              ""
              "!gh auth git-credential"
            ];
          };

          commit.gpgsign = true;

          github.user = "kra3";
        };
      };
    };
}
