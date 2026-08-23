{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.mcp-nixos.packages.${pkgs.system}.mcp-nixos ];
}
