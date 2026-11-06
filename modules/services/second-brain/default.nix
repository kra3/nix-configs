{
  # sutala's always-on copies of second brains: per brain, a git work tree synced with its hub
  # repo by a system timer, plus a local MCP server for Claude Code in ~/<claudeDir> (also
  # reachable from the phone through Remote Control). Nothing listens on the network.
  # Macs use the Home Manager module home-second-brain instead.
  flake.nixosModules.services-second-brain-default =
    {
      config,
      lib,
      pkgs,
      inputs,
      flakeLib,
      ...
    }:
    let
      cfg = config.services.secondBrain;
      sb = flakeLib.second-brain-packages;
      user = "second-brain";
      baseDir = "/srv/appdata/second-brain";
      syncScript = sb.mkSync pkgs;
      enabled = lib.filterAttrs (_: b: b.enable) cfg.brains;
      syncing = lib.filterAttrs (_: b: b.sync.enable) enabled;
      withMcp = lib.filterAttrs (_: b: b.mcp.enable) enabled;
      withRemote = lib.filterAttrs (_: b: b.mcp.enable && b.remoteControl.enable) enabled;
      claude = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      mcpFor =
        name: b:
        sb.mkMcp pkgs {
          inherit name;
          inherit (b) vaultDir;
        };

      common =
        flakeLib.deployment-hardening.mkServiceSandbox {
          readWritePaths = [ baseDir ];
        }
        // {
          User = user;
          Group = user;
          UMask = "0007";
          ProtectProc = "invisible";
        };
    in
    {
      options.services.secondBrain.brains = lib.mkOption {
        default = { };
        description = "Second brains kept on this host, by name (e.g. home).";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, config, ... }:
            {
              options = {
                enable = lib.mkEnableOption "this second brain" // {
                  default = true;
                };
                vaultDir = lib.mkOption {
                  type = lib.types.str;
                  default = "${baseDir}/${name}/vault";
                  description = "Server copy of the vault: a git work tree synced with the hub repo.";
                };
                gitDir = lib.mkOption {
                  type = lib.types.str;
                  default = "${baseDir}/${name}/vault.git";
                  description = "The vault's git dir, kept outside the vault.";
                };
                claudeDir = lib.mkOption {
                  type = lib.types.str;
                  default = "second-brain/${name}";
                  description = "Directory under kra3's home where Claude Code gets this brain's tools.";
                };
                sync = {
                  enable = lib.mkEnableOption "two-way git sync with the hub repo (needs the deploy key in sops)";
                  remote = lib.mkOption {
                    type = lib.types.str;
                    example = "git@github.com:kra3/second-brain.git";
                    description = "SSH URL of the hub repo every device pushes to; sutala uses a deploy key.";
                  };
                  interval = lib.mkOption {
                    type = lib.types.str;
                    default = "5min";
                  };
                  deployKeySecret = lib.mkOption {
                    type = lib.types.str;
                    default = "second-brain.${name}.git.deploy_key";
                    description = "sops key holding the deploy key (`just second-brain-secrets ${name}`).";
                  };
                };
                mcp.enable = lib.mkEnableOption "the local MCP server for Claude Code in ~/${config.claudeDir}" // {
                  default = true;
                };
                remoteControl = {
                  enable = lib.mkEnableOption ''
                    an always-on `claude remote-control` in ~/${config.claudeDir} (kra3 user service,
                    lingering), so the Claude app can open a session on this brain at any time.
                    Needs a one-time `claude` login as kra3
                  '';
                  permissionMode = lib.mkOption {
                    type = lib.types.enum [
                      "default"
                      "acceptEdits"
                      "plan"
                    ];
                    default = "default";
                    description = "Permission mode for sessions opened from the phone; acceptEdits skips approving each file edit.";
                  };
                };
              };
            }
          )
        );
      };

      config = lib.mkIf (enabled != { }) {
        users.users.${user} = {
          isSystemUser = true;
          group = user;
          home = "${baseDir}/state";
        };
        users.groups.${user} = { };
        # kra3 opens server copies in desktop Obsidian here and runs the MCP servers.
        users.users.kra3.extraGroups = [ user ];

        systemd.tmpfiles.rules = [
          "d ${baseDir} 0750 ${user} ${user} - -"
          "d ${baseDir}/state 0700 ${user} ${user} - -"
        ]
        ++ lib.concatLists (
          lib.mapAttrsToList (_: b: [
            "d ${dirOf b.vaultDir} 0750 ${user} ${user} - -"
            "d ${b.vaultDir} 2770 ${user} ${user} - -"
            # kra3 edits the same files under a 022 umask; default ACLs keep everything
            # group-writable so the sync service can still update it.
            "A+ ${b.vaultDir} - - - - group:${user}:rwX,default:group:${user}:rwX,default:mask::rwX"
          ]) enabled
        );

        sops.secrets = lib.mapAttrs' (_: b: lib.nameValuePair b.sync.deployKeySecret { }) syncing;

        programs.ssh.knownHosts = lib.mkIf (syncing != { }) {
          "github.com".publicKey =
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };

        systemd.services = lib.mapAttrs' (
          name: b:
          lib.nameValuePair "second-brain-${name}-sync" {
            description = "Two-way git sync of the ${name} second brain";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            environment = {
              VAULT_DIR = b.vaultDir;
              VAULT_GIT_DIR = b.gitDir;
              REMOTE = b.sync.remote;
              SYNC_HOST = config.networking.hostName;
            };
            serviceConfig = common // {
              Type = "oneshot";
              ExecStart = lib.getExe syncScript;
              # 75 = remote unreachable; changes are committed locally and the next run catches up.
              SuccessExitStatus = [ 75 ];
              LoadCredential = [ "deploy-key:${config.sops.secrets.${b.sync.deployKeySecret}.path}" ];
            };
          }
        ) syncing;

        systemd.timers = lib.mapAttrs' (
          name: b:
          lib.nameValuePair "second-brain-${name}-sync" {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "2min";
              OnUnitActiveSec = b.sync.interval;
            };
          }
        ) syncing;

        environment.systemPackages = lib.mapAttrsToList mcpFor withMcp;

        # User services for Remote Control must outlive logins and start at boot.
        users.users.kra3.linger = lib.mkIf (withRemote != { }) true;

        home-manager.users.kra3.systemd.user.services = lib.mapAttrs' (
          name: b:
          lib.nameValuePair "second-brain-${name}-remote" {
            Unit.Description = "Claude Code Remote Control for the ${name} second brain";
            Service = {
              WorkingDirectory = "%h/${b.claudeDir}";
              ExecStart = lib.escapeShellArgs [
                "${claude}/bin/claude"
                "remote-control"
                "--name"
                "second-brain-${name}"
                "--permission-mode"
                b.remoteControl.permissionMode
              ];
              # Spawned sessions run git, ripgrep etc. from the user's profile.
              Environment = [
                "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/kra3/bin:/run/current-system/sw/bin"
              ];
              Restart = "always";
              # Back off from 30 s up to an hour, so a hard failure (not logged in, folder not yet
              # trusted) stays quiet instead of retrying every 30 s.
              RestartSec = 30;
              RestartSteps = 8;
              RestartMaxDelaySec = 3600;
            };
            Install.WantedBy = [ "default.target" ];
          }
        ) withRemote;

        home-manager.users.kra3.home.file = lib.mkMerge (
          lib.mapAttrsToList (
            name: b:
            lib.mapAttrs' (f: v: lib.nameValuePair "${b.claudeDir}/${f}" v) (
              sb.claudeDirFiles {
                inherit name;
                inherit (b) vaultDir;
                mcp = mcpFor name b;
              }
            )
          ) withMcp
        );
      };
    };
}
