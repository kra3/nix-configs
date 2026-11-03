{
  flake.nixosModules.services-health-recomp-log =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      stateDir = "/srv/appdata/recomp-log";
      port = 8787;
      # Authelia username whose existing browser-held log is seeded from
      # recomp-log/data.json on first start (skipped once that user has rows).
      importUser = "kra3";

      recomp-log = pkgs.rustPlatform.buildRustPackage {
        pname = "recomp-log";
        version = "0.1.0";
        src = lib.fileset.toSource {
          root = ./recomp-log;
          fileset = lib.fileset.unions [
            ./recomp-log/Cargo.toml
            ./recomp-log/Cargo.lock
            ./recomp-log/index.html
            ./recomp-log/src
          ];
        };
        cargoLock.lockFile = ./recomp-log/Cargo.lock;
        meta.mainProgram = "recomp-log";
      };
    in
    {
      users.users.recomp-log = {
        isSystemUser = true;
        group = "recomp-log";
      };
      users.groups.recomp-log = { };

      systemd.tmpfiles.rules = [ "d ${stateDir} 0750 recomp-log recomp-log - -" ];

      systemd.services.recomp-log = {
        description = "Recomp Log training tracker (Rust + SQLite)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          HOST = "127.0.0.1";
          PORT = toString port;
          DB_FILE = "${stateDir}/recomp-log.db";
          # Set by nginx after Authelia forward-auth (see flakeLib.nginx).
          USER_HEADER = "Remote-User";
        };
        preStart = ''
          ${recomp-log}/bin/recomp-log import ${./recomp-log/data.json} ${lib.escapeShellArg importUser}
        '';
        serviceConfig =
          flakeLib.deployment-hardening.mkServiceSandbox {
            readWritePaths = [ stateDir ];
          }
          // {
            User = "recomp-log";
            Group = "recomp-log";
            ExecStart = "${recomp-log}/bin/recomp-log";
            Restart = "on-failure";
            RestartSec = 5;
            MemoryMax = "64M";
            PrivateDevices = true;
          };
      };

      services.nginx.virtualHosts."recomp.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://127.0.0.1:${toString port}";
        websockets = false;
        forwardAuth = true;
      };
    };
}
