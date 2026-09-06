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
        bind = "0.0.0.0";
        port = 6379;
        save = [
          [
            900
            1
          ]
          [
            300
            10
          ]
          [
            60
            10000
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

      # allow containers on br-life to reach redis
      networking.firewall.interfaces.br-life.allowedTCPPorts = [ 6379 ];
    };
}
