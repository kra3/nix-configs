{ pkgs, ... }:
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

  services.logrotate.enable = true;
  systemd.timers.logrotate.timerConfig.OnCalendar = "*-*-* 00,12:00:00";

  services.journald.extraConfig = ''
    SystemMaxUse=100M
    SystemMaxFileSize=25M
    MaxRetentionSec=12h
  '';

  time.timeZone = "UTC";
  system.stateVersion = "25.05";
}
