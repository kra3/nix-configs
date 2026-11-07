{
  flake.nixosModules.fail2ban =
    # Fail2ban intrusion prevention

    {
      config,
      lib,
      flakeLib,
      ...
    }:
    let
      defaultSetting = lib.mkDefault;
    in
    {
      services.fail2ban = {
        enable = true;

        # Loopback plus the two trusted hosts only (not the whole LAN, so a compromised LAN
        # device brute-forcing SSH/nginx still gets banned). Tailnet was never ignored; unchanged.
        ignoreIP = [
          "127.0.0.1/8"
          "192.168.1.10" # sutala
          "192.168.1.39" # surasa
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

          # Hosts without nginx (surasa) only get the sshd jail.
          nginx-http-auth.enabled = config.services.nginx.enable;
          nginx-botsearch.enabled = config.services.nginx.enable;
        };
      };

      systemd.services.fail2ban.serviceConfig = lib.mkMerge [
        (flakeLib.deployment-hardening.mkServiceSandbox {
          readWritePaths = [
            "/var/lib/fail2ban"
          ]
          ++ lib.optional config.services.nginx.enable "/var/log/nginx";
          capabilities = [ "CAP_NET_ADMIN" ];
          extraAddressFamilies = [ "AF_NETLINK" ];
        })
      ];

    };
}
