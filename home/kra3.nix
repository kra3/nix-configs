{ config, pkgs, ... }:
{
  home.stateVersion = "25.05";

  # Add user packages and services here.
  home.packages = with pkgs; [
    # Add user packages here.
  ];
}
