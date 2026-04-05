{ lib, ... }:
{
  programs.bash = {
    enable = true;

    historyControl = [
      "ignoreboth"
      "erasedups"
    ];
    historySize = 50000;
    historyFileSize = 100000;

    sessionVariables.HISTTIMEFORMAT = "%F %T ";

    shellOptions = [
      "histappend"
      "checkwinsize"
      "nocaseglob"
      "cdspell"
      "dirspell"
      "extglob"
      "globstar"
      "autocd"
    ];

    initExtra = ''
      # Source common shell configuration
      [[ -f ~/.shell_common.sh ]] && source ~/.shell_common.sh

      # No accidental overwrites by redirection (can override with >|)
      set -o noclobber

      # Enhanced debug output (shows file:line:function when using bash -x)
      export PS4='+(''${BASH_SOURCE}:''${LINENO}): ''${FUNCNAME[0]:+''${FUNCNAME[0]}(): }'

      # Bash 5.1+ options
      if [[ ''${BASH_VERSINFO[0]} -eq 5 && ''${BASH_VERSINFO[1]} -ge 1 ]] || [[ ''${BASH_VERSINFO[0]} -gt 5 ]]; then
        shopt -s checkjobs
        shopt -s progcomp_alias
        shopt -s direxpand
        shopt -s globasciiranges
      fi

      # Completions
      if [[ -r /usr/share/bash-completion/bash_completion ]]; then
        source /usr/share/bash-completion/bash_completion
      elif [[ -r /etc/bash_completion ]]; then
        source /etc/bash_completion
      fi
      complete -d cd

      # Prompt
      if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
      else
        PS1='\u@\h:\w\$ '
      fi
    '';

    profileExtra = ''
      if command -v pyenv &> /dev/null; then
        eval "$(pyenv init --path)"
      fi
    '';
  };
}
