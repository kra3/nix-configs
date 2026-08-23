{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.llm-agents.packages.${pkgs.system}.claude-code ];
}
