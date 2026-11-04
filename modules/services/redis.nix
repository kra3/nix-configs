{
  flake.nixosModules.services-redis =
    { config, ... }:
    {
      sops.secrets."db.redis_password" = {
        owner = "redis-default";
        group = "redis-default";
        mode = "0400";
      };

      services.redis.servers.default = {
        enable = true;
        # 0.0.0.0 on purpose: br-life/br-media-mgmt only exist once netavark starts a container on
        # them, so binding their gateway IPs at boot would silently drop them after a reboot.
        # Exposure is limited by the firewall below: 6379 is opened only on br-life and br-media-mgmt.
        bind = "0.0.0.0";
        port = 6379;
        save = [
          [
            3600
            1
          ]
        ];
        requirePassFile = config.sops.secrets."db.redis_password".path;
        maxclients = 50;
        settings = {
          rename-command = "FLUSHALL \"\"";
        };
      };

      # systemd sandboxing
      systemd.services.redis-default.serviceConfig = {
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        ReadWritePaths = [ "/var/lib/redis-default" ];
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        LockPersonality = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_UNIX"
        ];
        SystemCallArchitectures = "native";
      };

      # allow containers on br-life and br-media-mgmt to reach redis
      networking.firewall.interfaces.br-media-mgmt.allowedTCPPorts = [ 6379 ];
      networking.firewall.interfaces.br-life.allowedTCPPorts = [ 6379 ];
    };
}
