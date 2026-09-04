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
        version = "unstable-2024-08-17";
        src = pkgs.fetchFromGitHub {
          owner = "olimorris";
          repo = "tmux-pomodoro-plus";
          rev = "48ea2217e1e397a0f9bab30e80f3e7d3778671ae";
          sha256 = "sha256-QsA4i5QYOanYW33eMIuCtud9WD97ys4zQUT/RNUmGes=";
        };
      };
    in
    {
      imports = [
        # Replaces the unreliable @continuum-boot under Nix. Session is unnamed so
        # resurrect restores over it instead of colliding with "main"; `tmux ls` guards
        # against stacking empty sessions on reload. flock serializes the check+create
        # so a second concurrent invocation (e.g. a terminal app reopening several
        # windows at login) waits for the first instead of racing it into creating a
        # second bare session that fights continuum's restore.
        #
        # PATH matters here beyond just finding `tmux` to exec: the process that
        # starts the server has its environment captured as tmux's global
        # environment, which `run-shell` (continuum) and every pane inherit.
        # resurrect/continuum's own scripts call bare `tmux`/`ps`/etc, not
        # absolute paths — under launchd's minimal default PATH (no nix paths),
        # those calls fail silently and restore never runs, leaving a bare
        # session. Prepending tmux's store path here fixes it at the source.
        (flakeLib.login-autostart.mkLoginAgent {
          name = "tmux-server";
          description = "Start tmux server at login (for continuum restore)";
          script = ''
            export PATH="${pkgs.tmux}/bin:$PATH"
            lock="''${TMPDIR:-/tmp}/tmux-server-start.lock"
            ${pkgs.flock}/bin/flock "$lock" sh -c '${pkgs.tmux}/bin/tmux ls >/dev/null 2>&1 || ${pkgs.tmux}/bin/tmux new-session -d'
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
          tmux-pomodoro-plus
        ];
        # continuum isn't listed here — it's sourced manually at the end of extraConfig
        # instead (ordering matters, see below).

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

          # Kill pane/window
          bind x kill-pane
          bind X kill-window

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

          # Lazygit popup
          bind g if-shell "command -v lazygit" \
            "display-popup -E -w 95% -h 95% -d '#{pane_current_path}' lazygit" \
            "display-popup -E -w 80% -h 80% -d '#{pane_current_path}'"

          # Git status popup
          bind G display-popup -E -w 70% -h 70% -d "#{pane_current_path}" \
            "git status; echo; echo 'Press enter to close'; read"

          # GitHub Dashboard popup
          bind D if-shell "command -v gh" \
            "display-popup -E -w 95% -h 95% -d '#{pane_current_path}' 'gh dash'" \
            "display-message 'gh not found. Install with: brew install gh'"

          # ============================================================================
          # Plugin Settings
          # ============================================================================

          # Resurrect — pin the save dir. The nixpkgs build defaults to ~/.tmux/resurrect
          # (pre-XDG); pinning survives version bumps and matches existing saves.
          set -g @resurrect-dir "${config.xdg.dataHome}/tmux/resurrect"
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-processes '~claude ~aider'

          # @continuum-boot dropped — login autostart is declared via the imports above.
          set -g @continuum-restore 'on'

          # Tmux-yank
          set -g @yank_selection 'primary'
          set -g @yank_selection_mouse 'clipboard'

          # Source continuum LAST: catppuccin resets status-right above, which would wipe
          # continuum's autosave hook if it loaded any earlier. .rtp tracks the plugin's
          # entry script across upstream layout changes.
          run-shell ${pkgs.tmuxPlugins.continuum.rtp}
        '';
      };

      # catppuccin.tmux loads the catppuccin plugin (from catppuccin/nix sources).
      # extraConfig runs after the plugin is loaded — customise window/status layout here.
      catppuccin.tmux.extraConfig = ''
        set -g @catppuccin_window_status_style "rounded"
        set -g @catppuccin_window_text "#W"
        set -g @catppuccin_window_current_text "#W"
        set -g @catppuccin_window_flags "icon"
        set -g @catppuccin_status_left_separator ""
        set -g @catppuccin_status_right_separator " "

        # ============================================================================
        # Status Line
        # ============================================================================

        set -g status-position bottom
        set -g status-justify "absolute-centre"
        set -g status-left-length 40
        set -g status-right-length 40

        set -g status-left "#{E:@catppuccin_status_session}"
        set -ag status-left "#{E:@catppuccin_status_application}"
        set -ag status-left "#{E:@catppuccin_status_directory}"

        set -g status-right " "
        set -agF status-right "#{E:@catppuccin_status_pomodoro_plus}"
        set -agF status-right "#{E:@catppuccin_status_battery}"
        set -agF status-right "#{E:@catppuccin_status_date_time}"
      '';
    };
}
