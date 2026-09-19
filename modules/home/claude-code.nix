{
  flake.homeManagerModules.home-claude-code = { inputs, pkgs, ... }: {
    home.packages = [
      inputs.llm-agents.packages.${pkgs.system}.claude-code
      pkgs.sox # audio I/O for Claude Code voice mode
    ];

    # settings.json and RTK.md are excluded: both are live-mutated at runtime
    # (settings.json by /config and plugin installs; RTK.md by `rtk init`).
    home.file = {
      ".claude/CLAUDE.md" = {
        source = ./claude-code/CLAUDE.md;
        force = true;
      };
      ".claude/statusline.sh" = {
        source = ./claude-code/statusline.sh;
        force = true;
      };
      ".claude/hooks/guard-bash.sh" = {
        source = ./claude-code/hooks/guard-bash.sh;
        executable = true;
        force = true;
      };
      ".claude/hooks/notify.sh" = {
        source = ./claude-code/hooks/notify.sh;
        executable = true;
        force = true;
      };
    };
  };
}
