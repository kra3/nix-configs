{
  flake.homeManagerModules.home-claude-code = { inputs, pkgs, ... }: {
    home.packages = [
      inputs.llm-agents.packages.${pkgs.system}.claude-code
      pkgs.sox # audio I/O for Claude Code voice mode
      pkgs.nodejs # required by some Claude Code plugin hooks (e.g. i-have-adhd, ponytail)
    ];
  };
}
