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
      vhost = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://unix:${socket}";
        websockets = false;
        forwardAuth = true;
        # JSON import of a full history.
        vhostExtraConfig = "client_max_body_size 4m;";
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
      # timed so the next daily ZFS snapshot (and so backup-usb) holds it.
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
        # backup-usb sends only sanoid's daily/monthly snapshots, and the daily
        # one is taken by sanoid's run on the hour after 23:59. Writing the copy
        # before then puts it in that snapshot, which goes to USB at 03:30.
        timerConfig = {
          OnCalendar = "*-*-* 23:30:00";
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };

      # Copies yesterday's step count from the phone (Home Assistant companion
      # app sensor) into the log, only where no steps were logged by hand. It runs
      # for the two previous days, so one missed run is caught up.
      sops.secrets."homeassistant.token" = { };
      systemd.services.fitness-steps-sync = {
        description = "Fill Fitness step counts from Home Assistant";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          DB_FILE = "${stateDir}/fitness.db";
          HA_URL = "http://127.0.0.1:8123";
          STEPS_ENTITY = "sensor.meghanadha_health_steps";
          FITNESS_USER = "kra3";
        };
        serviceConfig = sandbox // {
          Type = "oneshot";
          # Needs loopback to reach Home Assistant, nothing else.
          PrivateNetwork = false;
          IPAddressAllow = "localhost";
          IPAddressDeny = "any";
          LoadCredential = [ "token:${config.sops.secrets."homeassistant.token".path}" ];
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "fitness-steps-sync";
              runtimeInputs = [
                pkgs.curl
                pkgs.jq
                pkgs.coreutils
                fitness
              ];
              text = ''
                token=$(<"$CREDENTIALS_DIRECTORY/token")
                for ago in 2 1; do
                  day=$(date -d "today - $ago days" +%F)
                  # Local midnight to midnight; "+" in the offset must be escaped.
                  start=$(date -d "$day" +%FT%T%:z | sed 's/+/%2B/')
                  end=$(date -d "$day + 1 day" +%FT%T%:z | sed 's/+/%2B/')
                  # The sensor counts up through the day, so the day's total is its highest reading.
                  steps=$(curl -fsS --max-time 30 -H "Authorization: Bearer $token" \
                    "$HA_URL/api/history/period/$start?end_time=$end&filter_entity_id=$STEPS_ENTITY&minimal_response&no_attributes" |
                    jq -r '[.[0][]?.state | tonumber? | select(. > 0)] | max // empty')
                  if [ -z "$steps" ]; then
                    echo "$day: no step readings from $STEPS_ENTITY"
                    continue
                  fi
                  fitness fill "$FITNESS_USER" "$day" "steps=$(printf '%.0f' "$steps")"
                done
              '';
            }
          );
        };
      };
      systemd.timers.fitness-steps-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:20:00";
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };

      # Lets nginx open the 0660 socket in the 0750 runtime dir. Changing the
      # nginx unit means the switch restarts nginx once, so the group applies.
      systemd.services.nginx.serviceConfig.SupplementaryGroups = [ "fitness" ];

      services.nginx.virtualHosts."fitness.${config.vars.acme.domain}" = lib.recursiveUpdate vhost {
        # Liveness for the homepage tile, the one path without login (still
        # behind the CIDR allowlist). It returns no user data. The URI on
        # proxy_pass makes nginx send exactly /healthz, never the client's raw
        # URI (e.g. /api/x/../../healthz, which also matches this location),
        # and any client-sent Remote-User is dropped.
        locations."= /healthz" = {
          proxyPass = "http://unix:${socket}:/healthz";
          extraConfig = ''proxy_set_header Remote-User "";'';
        };
      };
    };
}
