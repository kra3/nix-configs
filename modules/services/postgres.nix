{
  flake.nixosModules.services-postgres =
  { lib, pkgs, config, ... }:
  {
    sops.secrets."db.ghostfolio_password" = {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
    };

    systemd.tmpfiles.rules = [
      "d /srv/databases 0755 root root - -"
      "d /srv/databases/postgresql 0700 postgres postgres - -"
    ];

    services.postgresql = {
      enable = true;
      dataDir = "/srv/databases/postgresql";
      settings = {
        listen_addresses = lib.mkForce "*";

        # connection limits
        max_connections = 50;

        # logging
        log_connections = true;
        log_disconnections = true;
        log_statement = "ddl";

        # auth
        password_encryption = "scram-sha-256";
      };
      ensureDatabases = [ "ghostfolio" ];
      ensureUsers = [
        {
          name = "ghostfolio";
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
          };
        }
      ];
      authentication = lib.mkOverride 10 ''
        # life containers connect from br-life (${config.vars.network.podmanSubnets.life}) via scram-sha-256
        host ghostfolio ghostfolio ${config.vars.network.podmanSubnets.life} scram-sha-256
        # all other local socket connections use peer (OS user must match pg user)
        local all all peer
        # loopback TCP for manual access
        host all all 127.0.0.1/32 scram-sha-256
      '';
    };

    # set DB passwords from sops secrets after postgresql is ready
    systemd.services.postgresql-set-passwords = {
      description = "Set PostgreSQL user passwords from sops secrets";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
      };
      script = ''
        GHOSTFOLIO_PW=$(cat ${config.sops.secrets."db.ghostfolio_password".path})
        ${lib.getExe' config.services.postgresql.package "psql"} -c "ALTER USER ghostfolio PASSWORD '$GHOSTFOLIO_PW'"
      '';
    };

    # systemd sandboxing
    systemd.services.postgresql.serviceConfig = {
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ReadWritePaths = [ "/srv/databases/postgresql" ];
      NoNewPrivileges = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
      LockPersonality = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
      SystemCallArchitectures = "native";
    };

    # allow containers on br-life to reach postgresql
    networking.firewall.interfaces.br-life.allowedTCPPorts = [ 5432 ];
  };
}
