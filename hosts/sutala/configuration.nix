{ config, pkgs, ... }:
{
  imports = [
    # ./hardware-configuration.nix
    ../../modules/nix.nix
    ../../users/kra3.nix
  ];

  networking.hostName = "sutala";

  home-manager.users.kra3 = import ../../home/kra3.nix;

  system.stateVersion = "25.05";
}
