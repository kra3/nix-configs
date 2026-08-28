{
  flake.homeManagerModules.home-claude-code = { inputs, pkgs, ... }: {
    home.packages = [
      inputs.llm-agents.packages.${pkgs.system}.claude-code
      pkgs.sox # audio I/O for Claude Code voice mode
    ];
  };
}
