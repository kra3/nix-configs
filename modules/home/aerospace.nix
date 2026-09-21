{
  flake.homeManagerModules.home-aerospace =
    { pkgs, ... }:
    {
      programs.aerospace = {
        enable = true;

        launchd.enable = true;

        settings = {
          automatically-unhide-macos-hidden-apps = true;

          accordion-padding = 30;
          default-root-container-layout = "tiles";
          default-root-container-orientation = "auto";

          enable-normalization-flatten-containers = true;
          enable-normalization-opposite-orientation-for-nested-containers = true;

          on-focused-monitor-changed = [ ];
          on-focus-changed = [ ];

          # Notify SketchyBar on switch; absolute path — aerospace's agent PATH lacks it.
          exec-on-workspace-change = [
            "/bin/bash"
            "-c"
            "${pkgs.sketchybar}/bin/sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
          ];

          key-mapping.preset = "qwerty";

          gaps = {
            inner.horizontal = 8;
            inner.vertical = 8;
            outer.left = 8;
            outer.bottom = 8;
            # Static gap below the SketchyBar bar (notch display: usable frame already excludes the top strip).
            outer.top = 18;
            outer.right = 8;
          };

          on-window-detected = [
            {
              "if"."app-id" = "com.apple.systempreferences";
              run = "layout floating";
            }
            {
              "if"."app-id" = "com.apple.calculator";
              run = "layout floating";
            }
          ];

          mode.main.binding = {
            alt-h = "focus left";
            alt-j = "focus down";
            alt-k = "focus up";
            alt-l = "focus right";

            # Ctrl for "move" matches niri's convention on sutala (Mod+Ctrl+hjkl).
            alt-ctrl-h = "move left";
            alt-ctrl-j = "move down";
            alt-ctrl-k = "move up";
            alt-ctrl-l = "move right";

            # Shift for monitor-focus matches niri's convention (Mod+Shift+hjkl);
            # both hosts are multi-monitor.
            alt-shift-h = "focus-monitor left";
            alt-shift-j = "focus-monitor down";
            alt-shift-k = "focus-monitor up";
            alt-shift-l = "focus-monitor right";

            alt-minus = "resize smart -50";
            alt-equal = "resize smart +50";

            alt-slash = "layout tiles horizontal vertical";
            alt-comma = "layout accordion horizontal vertical";
            alt-shift-space = "layout floating tiling";
            alt-f = "macos-native-fullscreen";

            alt-1 = "workspace 1";
            alt-2 = "workspace 2";
            alt-3 = "workspace 3";
            alt-4 = "workspace 4";
            alt-5 = "workspace 5";
            alt-6 = "workspace 6";
            alt-7 = "workspace 7";
            alt-8 = "workspace 8";
            alt-9 = "workspace 9";

            alt-ctrl-1 = "move-node-to-workspace 1";
            alt-ctrl-2 = "move-node-to-workspace 2";
            alt-ctrl-3 = "move-node-to-workspace 3";
            alt-ctrl-4 = "move-node-to-workspace 4";
            alt-ctrl-5 = "move-node-to-workspace 5";
            alt-ctrl-6 = "move-node-to-workspace 6";
            alt-ctrl-7 = "move-node-to-workspace 7";
            alt-ctrl-8 = "move-node-to-workspace 8";
            alt-ctrl-9 = "move-node-to-workspace 9";

            alt-tab = "workspace-back-and-forth";
            alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

            alt-q = "close";
            alt-enter = ''exec-and-forget osascript -e "tell application \"Ghostty\" to new window"'';

            alt-shift-semicolon = "mode service";
            alt-r = "mode resize";

            cmd-h = [ ];
            cmd-alt-h = [ ];
          };

          mode.service.binding = {
            esc = [
              "reload-config"
              "mode main"
            ];
            r = [
              "flatten-workspace-tree"
              "mode main"
            ];
            f = [
              "layout floating tiling"
              "mode main"
            ];
            backspace = [
              "close-all-windows-but-current"
              "mode main"
            ];

            alt-shift-h = [
              "join-with left"
              "mode main"
            ];
            alt-shift-j = [
              "join-with down"
              "mode main"
            ];
            alt-shift-k = [
              "join-with up"
              "mode main"
            ];
            alt-shift-l = [
              "join-with right"
              "mode main"
            ];
          };

          mode.resize.binding = {
            h = "resize width -50";
            j = "resize height +50";
            k = "resize height -50";
            l = "resize width +50";
            minus = "resize smart -50";
            equal = "resize smart +50";
            enter = "mode main";
            esc = "mode main";
          };
        };
      };
    };
}
