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
      # The coach's tools (`fitness coach ...`, including the MCP server), fixed to
      # this database and user. kra3 may run only this, and only as `fitness`
      # (sudo rule below), so the login user never holds the database itself.
      coachTool = pkgs.writeShellApplication {
        name = "fitness-coach";
        text = ''
          export DB_FILE=${stateDir}/fitness.db FITNESS_USER=kra3
          exec ${lib.getExe fitness} coach "$@"
        '';
      };
      coachRun = [
        "/run/wrappers/bin/sudo"
        "-n"
        "-u"
        "fitness"
        (lib.getExe coachTool)
      ];
      # Phone nudges through Home Assistant: `fitness remind` prints a message when
      # there is something to remind about (nothing logged yet today, supplements
      # not ticked, no coach check-in for a week), and it is sent to the phone.
      # Times are server local time; a missed run is not caught up.
      reminderService = kind: {
        description = "Fitness ${kind} reminder to the phone";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          DB_FILE = "${stateDir}/fitness.db";
          HA_URL = "http://127.0.0.1:8123";
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
              name = "fitness-reminder-${kind}";
              runtimeInputs = [
                pkgs.curl
                pkgs.jq
                fitness
              ];
              text = ''
                msg=$(fitness remind "$FITNESS_USER" ${kind})
                if [ -z "$msg" ]; then
                  exit 0
                fi
                token=$(<"$CREDENTIALS_DIRECTORY/token")
                curl -fsS --max-time 30 -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
                  -d "$(jq -n --arg m "$msg" '{title: "Fitness", message: $m}')" \
                  "$HA_URL/api/services/notify/mobile_app_meghanadha"
              '';
            }
          );
        };
      };
      reminderTimer = when: {
        wantedBy = [ "timers.target" ];
        timerConfig.OnCalendar = when;
      };
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
          # Phone shortcut (Lose It via Apple Health): POST /api/ingest with this
          # token fills calories and protein for kra3. The service creates the
          # token file on first start; read it with `sudo cat`.
          INGEST_TOKEN_FILE = "${stateDir}/ingest-token";
          INGEST_USER = "kra3";
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

      # Copies health readings Home Assistant already has (phone and scale) into
      # the log for the two previous days (so one missed run is caught up), only
      # into fields that are still empty: anything logged by hand is kept.
      sops.secrets."homeassistant.token" = { };
      systemd.services.fitness-health-sync = {
        description = "Fill Fitness steps, sleep, weight and body fat from Home Assistant";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          DB_FILE = "${stateDir}/fitness.db";
          HA_URL = "http://127.0.0.1:8123";
          FITNESS_USER = "kra3";
        };
        serviceConfig = sandbox // {
          Type = "oneshot";
          # Needs Home Assistant, nothing else. Its published port 127.0.0.1:8123
          # is NATed to the container on the home-auto bridge, and the unit's
          # firewall checks the address after that, so loopback alone times out.
          PrivateNetwork = false;
          IPAddressAllow = [
            "localhost"
            config.vars.network.podmanSubnets.homeAuto
          ];
          IPAddressDeny = "any";
          LoadCredential = [ "token:${config.sops.secrets."homeassistant.token".path}" ];
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "fitness-health-sync";
              runtimeInputs = [
                pkgs.curl
                pkgs.jq
                pkgs.coreutils
                pkgs.gnused
                fitness
              ];
              text = ''
                token=$(<"$CREDENTIALS_DIRECTORY/token")

                # reading <entity> <day> <max|first>: one number from the readings
                # recorded during that local day, or nothing. HA's history also
                # returns the state carried in from before midnight; it is skipped.
                reading() {
                  local start end from
                  start=$(date -d "$2" +%FT%T%:z)
                  end=$(date -d "$2 + 1 day" +%FT%T%:z)
                  from=$(date -d "$2" +%s)
                  curl -fsS --max-time 30 -H "Authorization: Bearer $token" \
                    "$HA_URL/api/history/period/''${start//+/%2B}?end_time=''${end//+/%2B}&filter_entity_id=$1&minimal_response&no_attributes" |
                    jq -r --argjson from "$from" --arg pick "$3" '
                      [.[0][]?
                       | select((.last_changed // "" | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch 0) > $from)
                       | .state | tonumber? | select(. > 0)]
                      | if length == 0 then empty elif $pick == "max" then max else .[0] end'
                }

                for ago in 2 1; do
                  day=$(date -d "today - $ago days" +%F)
                  fields=()
                  # Phone (Health app via the HA companion app): steps count up
                  # through the day; sleep is minutes, written the morning after.
                  if v=$(reading sensor.meghanadha_health_steps "$day" max) && [ -n "$v" ]; then
                    fields+=("steps=$(printf '%.0f' "$v")")
                  fi
                  if v=$(reading sensor.meghanadha_sleep_duration "$day" max) && [ -n "$v" ]; then
                    fields+=("sleep=$(jq -n --argjson m "$v" '($m / 15 | round) / 4')")
                  fi
                  # Withings scale: the first weigh-in of the day (weight and body fat %).
                  if v=$(reading sensor.office_room_withings_kra_weight "$day" first) && [ -n "$v" ]; then
                    fields+=("weight=$(printf '%.1f' "$v")")
                  fi
                  if v=$(reading sensor.office_room_withings_kra_fat_ratio "$day" first) && [ -n "$v" ]; then
                    fields+=("bodyfat=$(printf '%.1f' "$v")")
                  fi
                  if [ ''${#fields[@]} -eq 0 ]; then
                    echo "$day: no readings from Home Assistant"
                    continue
                  fi
                  fitness fill "$FITNESS_USER" "$day" "''${fields[@]}"
                done
              '';
            }
          );
        };
      };
      systemd.timers.fitness-health-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:20:00";
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };

      systemd.services.fitness-reminders-weigh-in = reminderService "weigh-in";
      systemd.services.fitness-reminders-food = reminderService "food";
      systemd.services.fitness-reminders-supps = reminderService "supps";
      systemd.services.fitness-reminders-checkin = reminderService "checkin";
      systemd.timers.fitness-reminders-weigh-in = reminderTimer "*-*-* 10:00:00";
      systemd.timers.fitness-reminders-food = reminderTimer "*-*-* 21:00:00";
      systemd.timers.fitness-reminders-supps = reminderTimer "*-*-* 20:30:00";
      systemd.timers.fitness-reminders-checkin = reminderTimer "Sun *-*-* 18:00:00";

      security.sudo.extraRules = [
        {
          users = [ "kra3" ];
          runAs = "fitness";
          commands = [
            {
              command = lib.getExe coachTool;
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
      # ~/fitness-coach: start Claude Code there (directly or via Remote Control)
      # for a check-in. Its .mcp.json brings in the fitness tools; CLAUDE.md the
      # check-in routine. `fitness-coach-cli summary` etc. work from any shell.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "fitness-coach-cli" ''exec ${lib.escapeShellArgs coachRun} "$@"'')
      ];
      home-manager.users.kra3.home.file = {
        "fitness-coach/.mcp.json".text = builtins.toJSON {
          mcpServers.fitness = {
            command = builtins.head coachRun;
            args = builtins.tail coachRun ++ [ "mcp" ];
          };
        };
        "fitness-coach/CLAUDE.md".source = ./coach/CLAUDE.md;
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
        # The phone shortcut posts here with a bearer token, so this one path
        # skips Authelia (still behind the CIDR allowlist). The app checks the
        # token and accepts only calories and protein for one user. As above,
        # the fixed URI is what reaches the app, and a client Remote-User is dropped.
        locations."= /api/ingest" = {
          proxyPass = "http://unix:${socket}:/api/ingest";
          extraConfig = ''
            proxy_set_header Remote-User "";
            client_max_body_size 4k;
          '';
        };
      };
    };
}
