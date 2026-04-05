#!/usr/bin/env bash
# Shell functions — sourced by bash and zsh
#
# Everything else is handled declaratively:
#   env vars / PATH / aliases  → shell/common/default.nix
#   LS_COLORS                  → home.sessionVariables (vivid at build time)
#   LESSOPEN                   → programs.lesspipe
#   GPG_TTY                    → services.gpg-agent shell integration
#   FZF keybindings/command    → programs.fzf
#   zoxide init                → programs.zoxide shell integration
#   machine-local / work funcs → ~/.shell_local (not tracked in git)

# ============================================================================
# Functions
# ============================================================================

# Calculator
calc() { echo "$*" | bc -l; }

# Note-taking with vimwiki
n() { vim -c "VimwikiIndex"; }

# ============================================================================
# Tmux Functions
# ============================================================================

# Sesh integration — quick session connect
ts() {
    if [ -z "$1" ]; then
        if command -v sesh &> /dev/null && command -v fzf &> /dev/null; then
            local session
            session=$(sesh list -i | perl -pe 's/\\u\{([0-9a-f]+)\}/chr(hex($1))/gie' | fzf --height 40% --reverse --border --prompt '⚡ ' \
                --color 'fg:#cdd6f4,bg:#1e1e2e,hl:#cba6f7' \
                --color 'fg+:#cdd6f4,bg+:#313244,hl+:#cba6f7' \
                --color 'info:#89b4fa,prompt:#cba6f7,pointer:#f38ba8')
            [ -n "$session" ] && sesh connect "$session"
        else
            echo "sesh or fzf not found"
        fi
    else
        sesh connect "$1"
    fi
}

# Quick tmux session for current directory
tn() {
    local session_name="${1:-$(basename "$PWD")}"
    tmux new-session -A -s "$session_name"
}

# Kill tmux session with fzf
tk() {
    if [ -z "$1" ]; then
        local session
        session=$(tmux list-sessions -F '#S' | fzf --height 40% --reverse --prompt 'Kill session: ')
        [ -n "$session" ] && tmux kill-session -t "$session"
    else
        tmux kill-session -t "$1"
    fi
}

# Tmux session switcher (works from inside tmux)
tw() {
    if [ -n "$TMUX" ]; then
        local session current_session
        current_session=$(tmux display-message -p '#S')
        session=$(tmux list-sessions -F '#S' | command grep -v "^${current_session}$" | fzf --height 40% --reverse --prompt 'Switch to: ')
        [ -n "$session" ] && tmux switch-client -t "$session"
    else
        echo "Not in a tmux session"
    fi
}

# Tmux window switcher (works from inside tmux)
twd() {
    if [ -n "$TMUX" ]; then
        local window
        window=$(tmux list-windows -a -F '#S:#I:#W' | fzf --height 40% --reverse --prompt 'Go to window: ')
        [ -n "$window" ] && tmux switch-client -t "$(echo "$window" | awk -F: '{print $1":"$2}')"
    else
        echo "Not in a tmux session"
    fi
}

# List all tmux sessions
tls() {
    if command -v tmux &> /dev/null; then
        echo "Active tmux sessions:"
        tmux list-sessions 2>/dev/null || echo "No active sessions"
    fi
}

# Edit tmux config
tedit() { ${EDITOR:-vim} ~/.config/tmux/tmux.conf; }

# Reload tmux config
treload() {
    tmux source-file ~/.config/tmux/tmux.conf
    echo "Tmux config reloaded"
}

# ============================================================================
# Local Configuration
# ============================================================================

# Machine-local config not tracked in git (work functions, secrets, etc.)
[ -f ~/.shell_local ] && source ~/.shell_local
