{
  flake.homeManagerModules.home-shell-readline = { ... }: {
    programs.readline = {
      enable = true;
      extraConfig = ''
        # ============================================================================
        # Completion Behavior
        # ============================================================================

        set completion-ignore-case on
        set completion-map-case on
        set show-all-if-ambiguous on
        set show-all-if-unmodified on
        set colored-stats on
        set colored-completion-prefix on
        set menu-complete-display-prefix on
        set mark-symlinked-directories on
        set visible-stats on
        set mark-directories on

        # ============================================================================
        # Bell & Display
        # ============================================================================

        set bell-style none
        set page-completions on
        set completion-query-items 100
        set echo-control-characters off

        # ============================================================================
        # Modern Readline Features (7.0+)
        # ============================================================================

        set enable-bracketed-paste on
        set revert-all-at-newline on
        set show-mode-in-prompt on
        set vi-ins-mode-string "\1\e[6 q\2"
        set vi-cmd-mode-string "\1\e[2 q\2"

        # ============================================================================
        # Misc
        # ============================================================================

        set expand-tilde on
        set skip-completed-text on

        # ============================================================================
        # Vi Mode
        # ============================================================================

        set editing-mode vi

        # Vi Insert Mode
        set keymap vi-insert

        "\e[A": history-search-backward
        "\e[B": history-search-forward
        Control-p: previous-history
        Control-n: next-history
        Control-r: reverse-search-history
        Control-s: forward-search-history

        "jj": vi-movement-mode

        Control-a: beginning-of-line
        Control-e: end-of-line
        Control-l: clear-screen
        Control-w: backward-kill-word
        Control-k: kill-line
        Control-u: unix-line-discard
        Control-y: yank
        Control-d: delete-char

        "\t": complete
        "\e[Z": menu-complete-backward

        "\e[H": beginning-of-line
        "\e[F": end-of-line
        "\e[1;5C": forward-word
        "\e[1;5D": backward-word

        # Vi Command Mode
        set keymap vi-command

        "\e[A": history-search-backward
        "\e[B": history-search-forward
        Control-r: reverse-search-history

        "v": edit-and-execute-command

        Control-l: clear-screen
        Control-a: beginning-of-line
        Control-e: end-of-line

        "\e[H": beginning-of-line
        "\e[F": end-of-line
      '';
    };
  };
}
