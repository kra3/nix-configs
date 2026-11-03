{
  flake.nixosModules.services-redis =
    { config, lib, ... }:
    let
      # Podman bridge gateway = first host address of each subnet (10.3.x.0/24 -> 10.3.x.1).
      gw = subnet: lib.replaceStrings [ ".0/24" ] [ ".1" ] subnet;
      lifeGw = gw config.vars.network.podmanSubnets.life;
      mediaMgmtGw = gw config.vars.network.podmanSubnets.mediaMgmt;
    in
    {
      sops.secrets."db.redis_password" = {
        owner = "redis-default";
        group = "redis-default";
        mode = "0400";
      };

      services.redis.servers.default = {
        enable = true;
        # Loopback + the bridges whose containers use redis (ghostfolio on life, aiometadata on media-mgmt).
        # "-" prefix: don't fail startup if a bridge address is not up yet; ordering below normally ensures it is.
        bind = "127.0.0.1 -${lifeGw} -${mediaMgmtGw}";
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

      # bridges are created by the quadlet network units; bind after them
      systemd.services.redis-default = {
        after = [
          "life-network.service"
          "media-mgmt-network.service"
        ];
        wants = [
          "life-network.service"
          "media-mgmt-network.service"
        ];
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
