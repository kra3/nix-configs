# Fail2ban intrusion prevention

{ lib, ... }:
let
  defaultSetting = lib.mkDefault;
in
{
  services.fail2ban = {
    enable = true;

    ignoreIP = [
      "127.0.0.1/8"
      "192.168.1.0/24"
    ];

    jails = {
      DEFAULT = {
        settings = {
          banaction = defaultSetting "nftables-multiport";
          bantime = defaultSetting "1h";
          findtime = defaultSetting 600;
          maxretry = defaultSetting 5;
        };
      };

      sshd = {
        enabled = true;
        settings = {
          journalmatch = "_SYSTEMD_UNIT=sshd.service";
          findtime = 600;
        };
      };

      nginx-http-auth = {
        enabled = true;
      };

      nginx-botsearch = {
        enabled = true;
      };

      nginx-badbots = {
        enabled = true;
      };

      nginx-noscript = {
        enabled = true;
      };
    };
  };
}
