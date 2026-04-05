{ pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  home.packages = [ pkgs.zsh-completions ];

  home.file.".p10k.zsh".source = ./p10k.zsh;

  programs.zsh = {
    enable = true;

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 100000;
      extended = true;
      ignoreAllDups = true;
      expireDuplicatesFirst = true;
      share = true;
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    # Custom compinit with 24h caching
    completionInit = ''
      setopt EXTENDED_GLOB
      autoload -Uz compinit
      if [[ -n $HOME/.zcompdump(#qNmh+24) ]]; then
        compinit
      else
        compinit -C
      fi
    '';

    initContent = lib.mkMerge [
      # Must be at the very top — before any output (order 0)
      (lib.mkBefore ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')

      # fpath additions before compinit (order 550)
      (lib.mkOrder 550 (
        lib.optionalString isDarwin ''
          BREW_PREFIX="''${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)}"
          if [[ -n "$BREW_PREFIX" ]]; then
            fpath=("$BREW_PREFIX/share/zsh-completions" $fpath)
            fpath=("$BREW_PREFIX/share/zsh/site-functions" $fpath)
          fi
        ''
        + ''
          fpath=(~/.zsh/completions $fpath)
        ''
      ))

      # Main config — after compinit and plugins (default order)
      ''
        # Load p10k config
        [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

        # Source common shell configuration (after instant prompt)
        [[ -f ~/.shell_common.sh ]] && source ~/.shell_common.sh

        # ============================================================================
        # Completions
        # ============================================================================

        zstyle ':completion:*' menu select
        zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
        zstyle ':completion:*' group-name ""
        zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
        zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
        zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'
        zstyle ':completion:*' use-cache on
        zstyle ':completion:*' cache-path ~/.zsh/cache
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

        if command -v gh &> /dev/null; then
          eval "$(gh completion -s zsh)"
        fi

        if command -v aws_completer &> /dev/null; then
          autoload -Uz bashcompinit && bashcompinit
          complete -C aws_completer aws
        fi

        # ============================================================================
        # zsh Options
        # ============================================================================

        setopt HIST_SAVE_NO_DUPS
        setopt HIST_FIND_NO_DUPS
        setopt HIST_VERIFY
        setopt INC_APPEND_HISTORY
        setopt COMPLETE_IN_WORD
        setopt ALWAYS_TO_END
        setopt LIST_PACKED
        setopt NUMERIC_GLOB_SORT
        setopt AUTO_CD
        setopt AUTO_PUSHD
        setopt PUSHD_IGNORE_DUPS
        setopt PUSHD_SILENT
        setopt NO_CLOBBER
        setopt CORRECT

        # ============================================================================
        # Key Bindings
        # ============================================================================

        bindkey -e

        # Better history search (Ctrl+R/S for incremental search)
        bindkey '^R' history-incremental-search-backward
        bindkey '^S' history-incremental-search-forward

        # Up/Down arrow search history based on typed prefix (like .inputrc)
        autoload -U up-line-or-beginning-search down-line-or-beginning-search
        zle -N up-line-or-beginning-search
        zle -N down-line-or-beginning-search
        bindkey '^[[A' up-line-or-beginning-search
        bindkey '^[[B' down-line-or-beginning-search
      ''
    ];

    profileExtra = ''
      if command -v pyenv &> /dev/null; then
        eval "$(pyenv init --path)"
      fi
    '';
  };
}
