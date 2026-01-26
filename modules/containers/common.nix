{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.vim
  ];

  networking = {
    enableIPv6 = false;
    useHostResolvConf = false;
    firewall = {
      logRefusedConnections = true;
      logRefusedPackets = true;
      logRefusedUnicastsOnly = true;
    };
  };

  time.timeZone = "UTC";
  system.stateVersion = "25.05";
}
