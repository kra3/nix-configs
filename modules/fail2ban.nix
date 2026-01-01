# Fail2ban intrusion prevention

{
  services.fail2ban = {
    enable = true;
    banaction = "nftables-multiport";
    bantime = "1h";
    maxretry = 5;
    ignoreIP = [
      "127.0.0.1/8"
      "192.168.1.0/24"
    ];
    jails = {
      sshd = {
        enabled = true;
        settings = {
          backend = "systemd";
          journalmatch = "_SYSTEMD_UNIT=sshd.service";
          findtime = 600;
        };
      };
    };
  };
}
