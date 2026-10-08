{
  flake.homeManagerModules.home-tmux =
    {
      pkgs,
      lib,
      config,
      flakeLib,
      ...
    }:
    let
      tmux-pomodoro-plus = pkgs.tmuxPlugins.mkTmuxPlugin {
        pluginName = "tmux-pomodoro-plus";
        rtpFilePath = "pomodoro.tmux";
        version = "unstable-2024-08-17";
        src = pkgs.fetchFromGitHub {
          owner = "olimorris";
          repo = "tmux-pomodoro-plus";
          rev = "48ea2217e1e397a0f9bab30e80f3e7d3778671ae";
          sha256 = "sha256-QsA4i5QYOanYW33eMIuCtud9WD97ys4zQUT/RNUmGes=";
        };
      };

      # Boot/restore drive resurrect's scripts directly (continuum's boot installer bakes a stale nix
      # store path into an unmanaged unit). Periodic save uses continuum's save-check script instead —
      # see continuumSave — since an external launchd/systemd timer can't reach the tmux socket.
      resurrectScripts = "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts";
      resurrectDir = "${config.xdg.dataHome}/tmux/resurrect";
      resurrectLastSaveFile = "${config.xdg.stateHome}/tmux/last-save";
      # Touched when a restore completes; `tm` (shell_common.sh) waits on it to attach after a headless restore.
      resurrectLastRestoreFile = "${config.xdg.stateHome}/tmux/last-restore";

      # resurrect's scripts shell out to bare `tmux`, so PATH/TMUX_TMPDIR must be set explicitly outside a tmux client context.
      tmuxEnvExports = ''
        export PATH="${pkgs.tmux}/bin:$PATH"
        ${lib.optionalString pkgs.stdenv.isLinux ''export TMUX_TMPDIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"''}
      '';

      # "$@" lets continuum's periodic trigger pass "quiet" while the manual C-s keybind keeps resurrect's spinner feedback.
      resurrectSave = pkgs.writeShellScript "tmux-resurrect-save" ''
        ${tmuxEnvExports}
        prev="$(readlink "${resurrectDir}/last" 2>/dev/null || true)"
        prevpanes=$(grep -c '^pane' "${resurrectDir}/$prev" 2>/dev/null || true); prevpanes=$((prevpanes + 0))
        "${resurrectScripts}/save.sh" "$@" || exit $?
        new="$(readlink "${resurrectDir}/last" 2>/dev/null || true)"
        newpanes=$(grep -c '^pane' "${resurrectDir}/$new" 2>/dev/null || true); newpanes=$((newpanes + 0))
        # Reject a clobber: paneless dump, or a >50% pane collapse vs the prev save (a thin/fresh
        # server) — restore would lose the real workspace. A legit big teardown just keeps the old
        # save until a stable server saves again.
        if [ -n "$new" ] && { [ "$newpanes" -eq 0 ] || { [ "$prevpanes" -gt 0 ] && [ "$((newpanes * 2))" -lt "$prevpanes" ]; }; }; then
          rm -f "${resurrectDir}/$new"
          [ -n "$prev" ] && ln -sfn "$prev" "${resurrectDir}/last"
          exit 0
        fi
        mkdir -p "$(dirname "${resurrectLastSaveFile}")"
        date +%s > "${resurrectLastSaveFile}"
      '';

      resurrectRestore = pkgs.writeShellScript "tmux-resurrect-restore" ''
        ${tmuxEnvExports}
        "${resurrectScripts}/restore.sh"
        # Marker so `tm` knows the headless restore finished and can attach.
        mkdir -p "$(dirname "${resurrectLastRestoreFile}")"
        date +%s > "${resurrectLastRestoreFile}"
      '';

      resurrectStatus = pkgs.writeShellScript "tmux-resurrect-status" ''
        if [ -f "${resurrectLastSaveFile}" ]; then
          elapsed=$(( ($(date +%s) - $(cat "${resurrectLastSaveFile}")) / 60 ))
          echo "''${elapsed}m"
        else
          echo "--"
        fi
      '';

      # continuum_save.sh is self-contained (reads @continuum-* options directly), so it's invoked
      # from status-right below without loading the rest of continuum's plugin.
      continuumSave = "${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh";
      catppuccinStatusModule = "${config.catppuccin.sources.tmux}/share/tmux-plugins/catppuccin/utils/status_module.conf";
      catppuccinTmuxScript = "${config.catppuccin.sources.tmux}/share/tmux-plugins/catppuccin/catppuccin.tmux";
      batteryScripts = "${pkgs.tmuxPlugins.battery}/share/tmux-plugins/battery/scripts";
      pomodoroScript = "${tmux-pomodoro-plus}/share/tmux-plugins/tmux-pomodoro-plus/scripts/pomodoro.sh";

      # sutala/surasa are battery-less servers; mac-work is a laptop that always has one.
      hasBatteryScript = pkgs.writeShellScript "tmux-has-battery" (
        if pkgs.stdenv.isDarwin then
          "echo yes"
        else
          "ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1 && echo yes || echo no"
      );

      # Window/separator styling: must be set before catppuccin's run-shell (built-in modules read
      # these while it sources).
      windowAndSeparatorConf = ''
        set -g @catppuccin_window_status_style "rounded"
        set -g @catppuccin_window_text "#W"
        set -g @catppuccin_window_current_text "#W"
        set -g @catppuccin_window_flags "icon"
        set -g @catppuccin_status_left_separator ""
        set -g @catppuccin_status_right_separator ""
      '';

      # This must live in its own file, sourced via `source-file`, not inlined directly:
      # tmux's %if inside status_module.conf silently fails to fire when everything is
      # inlined in the same top-level file as an earlier blocking run-shell (confirmed
      # empirically) -- one more level of source-file nesting avoids it.
      resurrectModuleConfFile = pkgs.writeText "tmux-resurrect-module.conf" ''
        %hidden MODULE_NAME="resurrect"
        set -ogq "@catppuccin_''${MODULE_NAME}_icon" " "
        set -ogqF "@catppuccin_''${MODULE_NAME}_color" "#{E:@thm_green}"
        set -ogq "@catppuccin_''${MODULE_NAME}_text" " #(${resurrectStatus})"
        set -ogqF "@catppuccin_status_''${MODULE_NAME}_icon_fg" "#{E:@thm_crust}"
        set -ogqF "@catppuccin_status_''${MODULE_NAME}_text_fg" "#{E:@thm_fg}"
        set -ogqF "@catppuccin_status_''${MODULE_NAME}_text_bg" "#{E:@thm_surface_0}"
        source-file "${catppuccinStatusModule}"
      '';
      resurrectModuleConf = ''source-file "${resurrectModuleConfFile}"'';
    in
    {
      imports = [
        # flock avoids racing a duplicate session; restore is a tmux-level hook below, not here.
        (flakeLib.login-autostart.mkLoginAgent {
          name = "tmux-server";
          description = "Start tmux server at login";
          script = ''
            ${tmuxEnvExports}
            lock="''${TMPDIR:-/tmp}/tmux-server-start.lock"
            ${pkgs.flock}/bin/flock "$lock" sh -c 'tmux ls >/dev/null 2>&1 || tmux new-session -d'
          '';
        })
      ];

      programs.tmux = {
        enable = true;

        terminal = "tmux-256color";
        mouse = true;
        baseIndex = 1;
        escapeTime = 10;
        keyMode = "vi";
        prefix = "C-a";
        sensibleOnTop = true;

        plugins = with pkgs.tmuxPlugins; [
          pain-control
          resurrect
          yank
          open
          battery
          {
            plugin = tmux-pomodoro-plus;
            # Its defaults (p, P, _) collide with paste-buffer / choose-buffer / pain-control's split;
            # f replaces find-window (C-w fzf finder covers it), and C-f/M-f derive from it.
            extraConfig = ''
              set -g @pomodoro_toggle 'f'
              set -g @pomodoro_skip 'B'
              set -g @pomodoro_cancel 'Q'
            '';
          }
        ];

        extraConfig = ''
          # ============================================================================
          # Terminal & Display
          # ============================================================================
          set -ag terminal-overrides ",xterm-256color:RGB"

          # Undercurl support
          set -as terminal-overrides ',*:Smulx=\E[4::%p1%dm'
          set -as terminal-overrides ',*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m'

          # Pane base index (programs.tmux only sets window base-index)
          setw -g pane-base-index 1

          # Renumber windows when one is closed
          set -g renumber-windows on

          # Increase repeat timeout
          set -sg repeat-time 400

          # Modern tmux 3.2+ features
          set -s extended-keys on
          set -s extended-keys-format csi-u
          set -s set-clipboard on
          set -g allow-passthrough on

          # Set terminal title
          set -g set-titles on
          set -g set-titles-string '#h ❐ #S ● #I #W'

          # Activity monitoring
          set -g monitor-activity on
          set -g visual-activity off

          # Automatic window rename
          setw -g automatic-rename on

          # Force Vi status keys (keyMode only sets mode-keys)
          set -g status-keys vi

          # Let panes/apps (vim autoread, clipboard sync, etc.) see terminal focus in/out
          set -g focus-events on

          # ============================================================================
          # Key Bindings
          # ============================================================================

          # New window with current path
          bind c new-window -c "#{pane_current_path}"

          # Pane swapping
          bind -r '{' swap-pane -U
          bind -r '}' swap-pane -D

          # Break pane to new window
          bind T break-pane

          # Merge pane from another window
          bind m choose-window 'join-pane -h -s "%%"'
          bind v choose-window 'join-pane -v -s "%%"'

          # Kill pane/window (confirm, as stock)
          bind x confirm-before -p "kill-pane #P? (y/n)" kill-pane
          bind X confirm-before -p "kill-window #W? (y/n)" kill-window

          # Last window (l is pain-control's pane-right) and mark pane (m is merge-pane)
          bind Tab last-window
          bind M select-pane -m

          # Quick session tree
          bind s choose-tree -Zs

          # Window reordering
          bind -r '<' swap-window -t -1 -d
          bind -r '>' swap-window -t +1 -d

          # ============================================================================
          # Copy Mode (Vi-style)
          # ============================================================================

          bind Enter copy-mode
          bind b list-buffers
          bind p paste-buffer
          bind P choose-buffer

          bind -T copy-mode-vi v send -X begin-selection
          bind -T copy-mode-vi C-v send -X rectangle-toggle
          bind -T copy-mode-vi Escape send -X cancel
          bind -T copy-mode-vi H send -X start-of-line
          bind -T copy-mode-vi L send -X end-of-line

          # ============================================================================
          # Session Management
          # ============================================================================

          # Last session
          bind A switch-client -l

          # Sesh session manager (C-a S)
          bind "S" run-shell "sesh connect \"$(
            sesh list -t --icons | fzf-tmux -p 80%,70% \
              --no-sort --ansi --border-label ' sesh ' --prompt '🪟  ' \
              --header '  ^t tmux ^a all ^g configs ^x zoxide ^d tmux kill ^f find' \
              --bind 'tab:down,btab:up' \
              --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
              --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
              --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
              --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
              --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -d 3 -t d . ~/src)' \
              --bind 'ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(🪟  )+reload(sesh list -t --icons)' \
              --preview-window 'right:55%' \
              --preview 'sesh preview {}'
          )\""

          # Window finder with fzf
          bind C-w display-popup -E -w 60% -h 60% \
            "tmux list-windows -a -F '#S:#I:#W' | fzf --height 40% --reverse --border-label ' windows ' --border --prompt '🪟  ' | cut -d: -f1,2 | xargs tmux switch-client -t"

          # Quick notes popup
          bind N display-popup -E -w 80% -h 80% 'sh -c "mkdir -p ~/notes; exec ''${EDITOR:-vim} ~/notes/tmux-scratch.md"'

          # Lazygit popup (absolute path — tmux server PATH lacks the nix profile)
          bind g display-popup -E -w 95% -h 95% -d "#{pane_current_path}" "${lib.getExe pkgs.lazygit}"

          # Git status popup
          bind G display-popup -E -w 70% -h 70% -d "#{pane_current_path}" \
            "git status; echo; echo 'Press enter to close'; read"

          # gh dash popup (absolute path — tmux server PATH lacks the nix profile)
          bind D display-popup -E -w 95% -h 95% -d "#{pane_current_path}" "${lib.getExe pkgs.gh} dash"

          # ============================================================================
          # Plugin Settings
          # ============================================================================

          # Resurrect — pin the save dir. The nixpkgs build defaults to ~/.tmux/resurrect
          # (pre-XDG); pinning survives version bumps and matches existing saves.
          set -g @resurrect-dir "${resurrectDir}"
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-processes '~claude ~aider'
          # Point continuum's periodic save at our paneless-dump-guarded wrapper instead of resurrect's raw save.sh.
          set -g @resurrect-save-script-path "${resurrectSave}"

          # Read by continuum_save.sh (see continuumSave); boot/restore stay on the login-agent + hook below.
          set -g @continuum-save-interval '15'

          # Restore only on a fresh headless server (server age + no attached client) — skip the interactive attach, which restore.sh would tear down.
          run-shell -b 'sleep 1; if [ $(( $(date +%s) - $(tmux display-message -p "#{start_time}") )) -lt 5 ] && [ -z "$(tmux list-clients 2>/dev/null)" ]; then "${resurrectRestore}"; fi'

          # Rebind C-s so manual saves also update the status indicator's timestamp.
          bind-key C-s run-shell "${resurrectSave}"

          # Tmux-yank
          set -g @yank_selection 'primary'
          set -g @yank_selection_mouse 'clipboard'

          # ============================================================================
          # Status Line
          # ============================================================================

          ${resurrectModuleConf}

          set-hook -gu client-light-theme
          set-hook -gu client-dark-theme
          set -gu @catppuccin_flavor
          set -g @catppuccin_flavor 'mocha'

          set -g status-style "bg=#{@thm_mantle}"
          set -g status-justify "left"
          set -g status-position bottom
          set -g allow-rename off
          set -wg automatic-rename on
          set -g automatic-rename-format "#{pane_current_command}"

          set -g status-left-length 100
          set -g status-left ""
          set -ga status-left "#{?client_prefix,#{#[bg=#{@thm_red},fg=#{@thm_mantle},bold]  #{=/16:#{session_name}} },#{#[bg=#{@thm_mantle},fg=#{@thm_green}]  #{=/16:#{session_name}} }}"
          set -ga status-left "#[bg=#{@thm_mantle},fg=#{@thm_overlay_0}]│"
          set -ga status-left "#[bg=#{@thm_mantle},fg=#{@thm_maroon}]  #{pane_current_command} "
          set -ga status-left "#[bg=#{@thm_mantle},fg=#{@thm_overlay_0}]│"
          set -ga status-left "#[bg=#{@thm_mantle},fg=#{@thm_blue}]  #{=/-20/...:#{b:pane_current_path}} "

          set -g status-right-length 100
          set -g status-right ""
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_green}]#{E:@catppuccin_resurrect_icon}#{E:@catppuccin_resurrect_text} "
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_overlay_0}]│"
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_red}] #{E:@catppuccin_pomodoro_plus_text} "
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_overlay_0}]│"
          %if "#{==:#(${hasBatteryScript}),yes}"
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_pink}]#{E:@catppuccin_battery_icon}#{E:@catppuccin_battery_text} "
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_overlay_0}]│"
          %endif
          set -ga status-right "#[bg=#{@thm_mantle},fg=#{@thm_blue}] 󰃰 %Y-%m-%d #(${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh)"

          set -g window-status-format "#[bg=#{@thm_mantle}]#{?window_bell_flag,#[fg=#{@thm_red} bold] ,#{?window_activity_flag,#[fg=#{@thm_yellow}] ,#[fg=#{@thm_peach}]}} #I#{?window_bell_flag,#[fg=#{@thm_red}],#{?window_activity_flag,#[fg=#{@thm_yellow}],#[fg=#{@thm_rosewater}]}}#{?#{||:#{<=:#{session_windows},5},#{||:#{==:#{e|-:#{window_index},#{active_window_index}},1},#{==:#{e|-:#{active_window_index},#{window_index}},1}}},: #W,} "
          set -g window-status-style "bg=#{@thm_mantle},fg=#{@thm_rosewater}"
          set -g window-status-last-style "bg=#{@thm_mantle},fg=#{@thm_peach}"
          set -g window-status-activity-style "bg=#{@thm_mantle},fg=#{@thm_red}"
          set -g window-status-bell-style "bg=#{@thm_mantle},fg=#{@thm_red},bold"
          set -gF window-status-separator "#[bg=#{@thm_mantle},fg=#{@thm_overlay_0}]|"
          set -g window-status-current-format "#[bg=#{@thm_peach},fg=#{@thm_mantle},bold] #I #[bg=#{@thm_mantle},fg=#{@thm_peach}] #W #{?window_zoomed_flag,󰁌 ,}"
          set -g window-status-current-style "bg=#{@thm_mantle},fg=#{@thm_peach}"

          # Unset these first: they're set with -ogq, so stale values survive a re-source.
          bind r {
            set -g @catppuccin_reset on
            set -gu @catppuccin_pomodoro_plus_text
            set -gu @catppuccin_battery_icon
            set -gu @catppuccin_battery_text
            source-file ~/.config/tmux/tmux.conf
            display-message "tmux.conf reloaded"
          }
        '';
      };

      # catppuccin.tmux loads the catppuccin plugin. This extraConfig renders before catppuccin's own
      # run-shell, so @thm_* isn't defined yet here — windowAndSeparatorConf needs no theme colors.
      catppuccin.tmux.extraConfig = ''
        ${windowAndSeparatorConf}

        # battery/pomodoro-plus normally interpolate their #{battery_icon}/#{pomodoro_status}
        # placeholders by rewriting status-right at their own (earlier) plugin load time, before
        # catppuccin has written those placeholders in — so it never fires. Set the resolved
        # #() calls directly instead; catppuccin's -ogq defaults then leave these alone.
        set -ogq @catppuccin_battery_icon "#(${batteryScripts}/battery_icon.sh) "
        set -ogq @catppuccin_battery_text " #(${batteryScripts}/battery_percentage.sh)"
        set -ogq @catppuccin_pomodoro_plus_text " #(${pomodoroScript})"
      '';
    };
}
