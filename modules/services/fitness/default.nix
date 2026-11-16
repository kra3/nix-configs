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
      claude = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
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

      # Apple Health values arrive from each phone's shortcut (POST /api/ingest);
      # this copies body values forward for everyone who logged in the last 14 days.
      systemd.services.fitness-carry = {
        description = "Carry Fitness body values forward";
        environment.DB_FILE = "${stateDir}/fitness.db";
        serviceConfig = sandbox // {
          Type = "oneshot";
          ExecStart = lib.getExe (
            pkgs.writeShellApplication {
              name = "fitness-carry";
              runtimeInputs = [
                pkgs.coreutils
                fitness
              ];
              text = ''
                fitness carry "$(date -d yesterday +%F)"
                fitness carry "$(date +%F)"
              '';
            }
          );
        };
      };
      systemd.timers.fitness-carry = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 06:20:00";
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
      };

      sops.secrets."homeassistant.token" = { };

      # No food reminder: food is logged in Lose It and reaches Apple Health, which
      # this server cannot read, so "nothing logged" would fire every evening. The
      # app's `fitness remind <user> food` still works if it is wanted again.
      systemd.services.fitness-reminders-weigh-in = reminderService "weigh-in";
      systemd.services.fitness-reminders-supps = reminderService "supps";
      systemd.services.fitness-reminders-checkin = reminderService "checkin";
      systemd.timers.fitness-reminders-weigh-in = reminderTimer "*-*-* 10:00:00";
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
      # ~/agents/fitness-coach: start Claude Code there (directly or via Remote Control)
      # for a check-in. Its .mcp.json brings in the fitness tools; CLAUDE.md the
      # check-in routine. `fitness-coach-cli summary` etc. work from any shell.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "fitness-coach-cli" ''exec ${lib.escapeShellArgs coachRun} "$@"'')
      ];
      home-manager.users.kra3.home.file = {
        "agents/fitness-coach/.mcp.json".text = builtins.toJSON {
          mcpServers.fitness = {
            command = builtins.head coachRun;
            args = builtins.tail coachRun ++ [ "mcp" ];
          };
        };
        "agents/fitness-coach/CLAUDE.md".source = ./coach/CLAUDE.md;
      };

      # Always-on Claude Code session for the coach, started at boot like
      # second-brain's: open "fitness-coach" in the Claude app (Remote Control) and
      # ask for the check-in. It runs in ~/agents/fitness-coach, so its .mcp.json and
      # CLAUDE.md apply. The default permission mode (not acceptEdits) is deliberate:
      # the coach has no business editing files, and each propose call is asked about.
      # Needs a one-time interactive `claude` login as kra3 (already done for
      # second-brain) and one interactive `claude` in the folder to trust it; until
      # then the unit fails quietly and backs off.
      users.users.kra3.linger = true;
      home-manager.users.kra3.systemd.user.services.fitness-coach-remote = {
        Unit.Description = "Claude Code Remote Control for the Fitness coach";
        Service = {
          WorkingDirectory = "%h/agents/fitness-coach";
          ExecStart = lib.escapeShellArgs [
            "${claude}/bin/claude"
            "remote-control"
            "--name"
            "fitness-coach"
            "--permission-mode"
            "default"
          ];
          Environment = [
            "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/kra3/bin:/run/current-system/sw/bin"
          ];
          Restart = "always";
          # Back off from 30 s up to an hour, so a hard failure (not logged in,
          # folder not yet trusted) stays quiet instead of retrying every 30 s.
          RestartSec = 30;
          RestartSteps = 8;
          RestartMaxDelaySec = 3600;
        };
        Install.WantedBy = [ "default.target" ];
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
        # The phone shortcut posts here with a per-user key, so this one exact
        # path skips Authelia (still behind the CIDR allowlist); /api/ingest/key
        # stays behind it. The fixed URI is what reaches the app, and a client
        # Remote-User is dropped. 256k fits a 400-day backfill.
        locations."= /api/ingest" = {
          proxyPass = "http://unix:${socket}:/api/ingest";
          extraConfig = ''
            proxy_set_header Remote-User "";
            client_max_body_size 256k;
          '';
        };
      };
    };
}
