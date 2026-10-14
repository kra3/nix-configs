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

      # Workspaces plus zoxide dirs; picking a dir opens a workspace there.
      workspacePicker = pkgs.writeShellScript "herdr-workspace-picker" ''
        export PATH=${
          pkgs.lib.makeBinPath [
            pkgs.fzf
            pkgs.jq
            pkgs.zoxide
            pkgs.coreutils
            pkgs.gawk
          ]
        }:$PATH
        pick=$(
          {
            "$HERDR_BIN_PATH" workspace list |
              jq -r '.result.workspaces[] | "ws\t\(.workspace_id)\t\(.label)"'
            zoxide query -l | awk -v h="$HOME" '{ p = $0; sub("^" h, "~", p); print "dir\t" $0 "\t" p }'
          } | fzf --delimiter '\t' --with-nth 3 --prompt 'workspace > '
        ) || exit 0
        kind=''${pick%%$'\t'*}
        rest=''${pick#*$'\t'}
        val=''${rest%%$'\t'*}
        case $kind in
          ws) "$HERDR_BIN_PATH" workspace focus "$val" ;;
          dir) "$HERDR_BIN_PATH" workspace create --cwd "$val" --label "$(basename "$val")" --focus ;;
        esac
      '';
      toml = pkgs.formats.toml { };
    in
    {
      options.programs.herdr.settings = lib.mkOption {
        type = toml.type;
        default = { };
        description = "herdr config.toml contents; override per user or host.";
      };

      config = {
        home.packages = [ herdr ];

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
            resize_mode = "prefix+shift+r";
            command = [
              {
                key = "prefix+shift+s";
                type = "popup";
                command = "${workspacePicker}";
                width = "60%";
                height = "60%";
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
            ];
          };
          ui = {
            agent_panel_sort = "spaces";
            tab_bar_position = "bottom";
            pane_outer_borders = false;
            prompt_new_tab_name = false;
            toast.delivery = "system";
            sidebar_start_collapsed = lib.mkDefault true;
            status_indicators = lib.mkDefault "symbols";
          };
          experimental.pane_history = true;
        };

        home.file.".claude/skills/herdr/SKILL.md".source =
          pkgs.runCommand "herdr-skill.md" { }
            "${herdr}/bin/herdr --skill > $out";
      };
    };
}
