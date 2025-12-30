{ config, pkgs, ... }:
{
  imports = [
    # ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nix.nix
    ../../users/kra3.nix
  ];

  networking.hostName = "sutala";
  networking.hostId = "d2a81622";

  boot.supportedFilesystems = [ "zfs" ];
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=3338665984
  '';

  home-manager.users.kra3 = import ../../home/kra3.nix;

  system.stateVersion = "25.05";
}
