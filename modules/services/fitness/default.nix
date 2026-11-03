{
  flake.nixosModules.services-fitness-default =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      stateDir = "/srv/appdata/fitness";
      port = 8787;

      fitness = pkgs.rustPlatform.buildRustPackage {
        pname = "fitness";
        version = "0.1.0";
        src = lib.fileset.toSource {
          root = ./app;
          fileset = lib.fileset.unions [
            ./app/Cargo.toml
            ./app/Cargo.lock
            ./app/index.html
            ./app/src
          ];
        };
        cargoLock.lockFile = ./app/Cargo.lock;
        meta.mainProgram = "fitness";
      };
    in
    {
      users.users.fitness = {
        isSystemUser = true;
        group = "fitness";
      };
      users.groups.fitness = { };

      systemd.tmpfiles.rules = [ "d ${stateDir} 0750 fitness fitness - -" ];

      systemd.services.fitness = {
        description = "Fitness training tracker (Rust + SQLite)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          HOST = "127.0.0.1";
          PORT = toString port;
          DB_FILE = "${stateDir}/fitness.db";
          # Set by nginx after Authelia forward-auth (see flakeLib.nginx).
          USER_HEADER = "Remote-User";
        };
        serviceConfig =
          flakeLib.deployment-hardening.mkServiceSandbox {
            readWritePaths = [ stateDir ];
          }
          // {
            User = "fitness";
            Group = "fitness";
            ExecStart = "${fitness}/bin/fitness";
            Restart = "on-failure";
            RestartSec = 5;
            MemoryMax = "64M";
            PrivateDevices = true;
          };
      };

      services.nginx.virtualHosts."fitness.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://127.0.0.1:${toString port}";
        websockets = false;
        forwardAuth = true;
      };
    };
}
