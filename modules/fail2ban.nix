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

        ignoreIP = [
          "127.0.0.1/8"
          config.vars.network.lanCidr
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
        };
      };

      systemd.services.fail2ban.serviceConfig = lib.mkMerge [
        (flakeLib.deployment-hardening.mkServiceSandbox {
          readWritePaths = [
            "/var/lib/fail2ban"
            "/var/log/nginx"
          ];
          capabilities = [ "CAP_NET_ADMIN" ];
          extraAddressFamilies = [ "AF_NETLINK" ];
        })
      ];

    };
}
