{ inputs, ... }:
{
  # Registered as a flake package too, so `nix flake check` (CI) builds it and
  # runs its cargo tests.
  perSystem =
    { lib, pkgs, ... }:
    {
      packages.fitness = pkgs.rustPlatform.buildRustPackage {
        pname = "fitness";
        version = (lib.importTOML ./app/Cargo.toml).package.version;
        # Link nixpkgs' SQLite (not the copy rusqlite can bundle), so flake
        # updates bring its security fixes.
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.sqlite ];
        src = lib.fileset.toSource {
          root = ./app;
          fileset = lib.fileset.unions [
            ./app/Cargo.toml
            ./app/Cargo.lock
            ./app/src
            ./app/index.html
            ./app/app.js
            ./app/app.css
            ./app/sw.js
            ./app/manifest.webmanifest
            ./app/icon-192.png
            ./app/icon-512.png
          ];
        };
        cargoLock.lockFile = ./app/Cargo.lock;
        meta.mainProgram = "fitness";
      };
    };

  flake.nixosModules.services-fitness-default =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      fitness = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.fitness;
      stateDir = "/srv/appdata/fitness";
      sandbox =
        flakeLib.deployment-hardening.mkServiceSandbox {
          readWritePaths = [ stateDir ];
        }
        // {
          User = "fitness";
          Group = "fitness";
          UMask = "0007";
          # Talks only over the unix socket, so it gets no network at all.
          PrivateNetwork = true;
          PrivateDevices = true;
        };
      # Unix socket instead of a TCP port: only root, the service and nginx (via
      # group membership below) can reach it, so nothing else on the host can
      # send a forged Remote-User header.
      socket = "/run/fitness/fitness.sock";
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
        after = [ "local-fs.target" ];
        environment = {
          LISTEN = "unix:${socket}";
          DB_FILE = "${stateDir}/fitness.db";
          # Set by nginx after Authelia forward-auth (see flakeLib.nginx).
          USER_HEADER = "Remote-User";
        };
        serviceConfig = sandbox // {
          ExecStart = "${fitness}/bin/fitness";
          RuntimeDirectory = "fitness";
          RuntimeDirectoryMode = "0750";
          Restart = "on-failure";
          RestartSec = 5;
          MemoryMax = "64M";
        };
      };

      # A clean single-file copy (VACUUM INTO) beside the live WAL database,
      # written before backup-usb's 03:30 run so that night's snapshot holds it.
      systemd.services.fitness-backup = {
        description = "Consistent copy of the Fitness database";
        environment.DB_FILE = "${stateDir}/fitness.db";
        serviceConfig = sandbox // {
          Type = "oneshot";
          ExecStart = "${fitness}/bin/fitness backup ${stateDir}/fitness-backup.db";
          MemoryMax = "64M";
        };
      };
      systemd.timers.fitness-backup = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:00:00";
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };

      # Lets nginx open the 0660 socket in the 0750 runtime dir. Changing the
      # nginx unit means the switch restarts nginx once, so the group applies.
      systemd.services.nginx.serviceConfig.SupplementaryGroups = [ "fitness" ];

      services.nginx.virtualHosts."fitness.${config.vars.acme.domain}" = lib.recursiveUpdate (flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://unix:${socket}";
        websockets = false;
        forwardAuth = true;
        # JSON import of a full history.
        vhostExtraConfig = "client_max_body_size 4m;";
      }) {
        # Liveness for the homepage tile, the one path without login (still
        # behind the CIDR allowlist). It returns no user data.
        locations."= /healthz".proxyPass = "http://unix:${socket}";
      };
    };
}
