{
  flake.nixosModules.services-second-brain-default =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      cfg = config.services.secondBrain;
      user = "second-brain";
      baseDir = "/srv/appdata/second-brain";
      stateDir = "${baseDir}/state";
      gitDir = "${baseDir}/vault.git";

      # Stable: unstable's fastmcp is marked broken against mcp 2.x.
      python = pkgs.python3.withPackages (ps: [ ps.fastmcp ]);
      mcpServer = pkgs.writeShellApplication {
        name = "second-brain-mcp";
        text = ''
          export VAULT_DIR=${lib.escapeShellArg cfg.vaultDir}
          exec ${python}/bin/python3 ${./mcp_server.py}
        '';
      };

      syncScript = pkgs.writeShellApplication {
        name = "second-brain-sync";
        runtimeInputs = [
          pkgs.git
          pkgs.openssh
          pkgs.coreutils
          pkgs.findutils
        ];
        text = builtins.readFile ./sync.sh;
      };

      sandbox = flakeLib.deployment-hardening.mkServiceSandbox {
        readWritePaths = [ baseDir ];
      };
      common = sandbox // {
        User = user;
        Group = user;
        UMask = "0007";
        ProtectProc = "invisible";
      };
    in
    {
      options.services.secondBrain = {
        vaultDir = lib.mkOption {
          type = lib.types.str;
          default = "${baseDir}/vault";
          description = "Server copy of the Obsidian vault: a git work tree synced with the hub repo.";
        };

        sync = {
          enable = lib.mkEnableOption "two-way git sync of the vault with its hub repo (history in ${gitDir})";
          remote = lib.mkOption {
            type = lib.types.str;
            example = "git@github.com:kra3/second-brain.git";
            description = "SSH URL of the hub repo the Mac and sutala both push to; sutala uses a deploy key.";
          };
          interval = lib.mkOption {
            type = lib.types.str;
            default = "5min";
            description = "How often sutala commits, rebases onto the hub and pushes.";
          };
        };

        mcp.enable = lib.mkEnableOption ''
          the local (stdio) MCP server for Claude Code on this host: ~/second-brain holds the
          .mcp.json that starts it, so a session there, or one driven by Remote Control from the
          phone, gets the vault tools without anything listening on the network
        '';
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.sync.enable || cfg.mcp.enable) {
          users.users.${user} = {
            isSystemUser = true;
            group = user;
            home = stateDir;
          };
          users.groups.${user} = { };
          # kra3 opens the server copy in desktop Obsidian on this host (no sync plugin there).
          users.users.kra3.extraGroups = [ user ];

          systemd.tmpfiles.rules = [
            "d ${baseDir} 0750 ${user} ${user} - -"
            "d ${cfg.vaultDir} 2770 ${user} ${user} - -"
            # kra3 edits the same files from desktop Obsidian on this host, under a 022 umask;
            # default ACLs keep everything group-writable so the sync service can still update it.
            "A+ ${cfg.vaultDir} - - - - group:${user}:rwX,default:group:${user}:rwX,default:mask::rwX"
            "d ${stateDir} 0700 ${user} ${user} - -"
          ];
        })

        (lib.mkIf cfg.sync.enable {
          sops.secrets."second-brain.git.deploy_key" = { };

          programs.ssh.knownHosts."github.com".publicKey =
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

          systemd.services.second-brain-sync = {
            description = "Two-way git sync of the second-brain vault";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            environment = {
              VAULT_DIR = cfg.vaultDir;
              VAULT_GIT_DIR = gitDir;
              REMOTE = cfg.sync.remote;
              SYNC_HOST = config.networking.hostName;
            };
            serviceConfig = common // {
              Type = "oneshot";
              ExecStart = lib.getExe syncScript;
              LoadCredential = [
                "deploy-key:${config.sops.secrets."second-brain.git.deploy_key".path}"
              ];
            };
          };

          systemd.timers.second-brain-sync = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "2min";
              OnUnitActiveSec = cfg.sync.interval;
            };
          };
        })

        (lib.mkIf cfg.mcp.enable {
          environment.systemPackages = [ mcpServer ];

          home-manager.users.kra3.home.file = {
            "second-brain/.mcp.json".text = builtins.toJSON {
              mcpServers.second-brain.command = lib.getExe mcpServer;
            };
            # Project settings: trust this one server and let Claude edit the vault outside the cwd.
            "second-brain/.claude/settings.json".text = builtins.toJSON {
              enabledMcpjsonServers = [ "second-brain" ];
              permissions.additionalDirectories = [ cfg.vaultDir ];
            };
            "second-brain/CLAUDE.md".text = ''
              # Second brain

              The vault is `${cfg.vaultDir}` (a git work tree; `second-brain-sync.timer` commits and
              pushes every few minutes, so never run git in it yourself). Read
              `${cfg.vaultDir}/CLAUDE.md` before doing anything: it holds the folder rules, the
              weekly review and the rule that Arun writes evergreen notes himself.

              Use the `second-brain` MCP tools (capture, search_notes, list_tasks, recent_changes,
              orphans, backlinks, ...) or edit the files directly.
            '';
          };
        })
      ];
    };
}
