{ lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  # Static environment variables — available in all shells including non-interactive
  home.sessionVariables = {
    EDITOR = "vim";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_CACHE_HOME = "$HOME/.cache";
    XDG_STATE_HOME = "$HOME/.local/state";
    CDPATH = ".:~:~/src";
    PAGER = "less";
    LESS = "-R -F -X -i";
    GRADLE_COMPLETION_UNQUALIFIED_TASKS = "true";
  };

  # LS_COLORS — catppuccin.vivid sets programs.vivid.activeTheme; home-manager
  # programs.vivid exports LS_COLORS at shell init. No manual generation needed.
  catppuccin.vivid.enable = true;

  # lesspipe — sets LESSOPEN so less can preview archives, images, etc.
  programs.lesspipe.enable = true;

  # PATH additions
  home.sessionPath = [
    "$HOME/bin"
    "$HOME/.local/bin"
  ] ++ lib.optionals isDarwin [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/opt/homebrew/opt/libpq/bin"
    "$HOME/Library/Application Support/Coursier/bin"
    "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
  ] ++ lib.optionals (!isDarwin) [
    "$HOME/.local/share/coursier/bin"
    "$HOME/.local/share/JetBrains/Toolbox/scripts"
  ];

  # Shared aliases — applied to all enabled shells (bash, zsh)
  home.shellAliases = {
    # eza
    ls = "eza";
    l = "eza -F";
    ll = "eza -lhF --git";
    la = "eza -lhaF --git";
    lla = "eza -al --git";
    lsd = "eza -lD";
    tree = "eza --tree";

    # bat
    cat = "bat --paging=never";
    less = "bat --paging=always";

    # Navigation
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";
    "....." = "cd ../../../..";
    "......" = "cd ../../../../..";
    "-" = "cd -";

    # Safety
    rm = "rm -iv";
    cp = "cp -v";
    mv = "mv -v";

    # Utilities
    vi = "vim";
    diff = "colordiff";
    cls = "clear";
    h = "history";
    path = ''echo -e "''${PATH//:/\n}"'';
    now = ''date +"%T"'';
    today = ''date +"%d-%m-%Y"'';
    mount = "mount | column -t";
    g = "git";
  } // lib.optionalAttrs isDarwin {
    brewup = "brew update; brew upgrade; brew cleanup; brew doctor";
    macjava = "/usr/libexec/java_home -V";
  };

  # Shell functions: wt/tmux helpers (~300 lines with heredocs — kept as file)
  home.file.".shell_common.sh".source = ./shell_common.sh;
}
