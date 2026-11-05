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
      publicUrl = "https://${cfg.mcp.publicHost}:${toString cfg.mcp.funnelPort}";

      # Stable: unstable's fastmcp is marked broken against mcp 2.x.
      python = pkgs.python3.withPackages (ps: [ ps.fastmcp ]);

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

        mcp = {
          enable = lib.mkEnableOption "remote MCP server for Claude, published via Tailscale Funnel";
          publicHost = lib.mkOption {
            type = lib.types.str;
            example = "sutala.tail1234.ts.net";
            description = "This node's MagicDNS name; Funnel serves the MCP server there.";
          };
          funnelPort = lib.mkOption {
            # Funnel only allows 443, 8443 and 10000; 443 on the tailnet IP is nginx's.
            type = lib.types.enum [
              8443
              10000
            ];
            default = 8443;
          };
          allowNewClients = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Accept new OAuth clients (dynamic registration and CIMD). Leave on until your own
              claude.ai connector (and Claude Code, if wanted) is connected, then turn it off: the
              endpoint is public, and anyone can register a client that looks just like Claude.
            '';
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 8765;
            description = "Loopback port of the MCP server; only Funnel reaches it.";
          };
        };
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
          # Root-owned; handed to the service via LoadCredential.
          sops.secrets."second-brain.mcp.oidc_client_secret" = { };

          systemd.services.second-brain-mcp = {
            description = "Remote MCP server for the second-brain vault";
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "authelia.service"
            ];
            wantedBy = [ "multi-user.target" ];
            environment = {
              VAULT_DIR = cfg.vaultDir;
              PUBLIC_URL = publicUrl;
              PORT = toString cfg.mcp.port;
              ALLOW_NEW_CLIENTS = if cfg.mcp.allowNewClients then "1" else "0";
              OIDC_DISCOVERY_URL = "https://auth.${config.vars.acme.domain}/.well-known/openid-configuration";
              OIDC_CLIENT_ID = "second-brain";
              # OAuth client registrations and FastMCP's token store; must survive restarts.
              FASTMCP_HOME = "${stateDir}/fastmcp";
              HOME = stateDir;
            };
            serviceConfig = common // {
              ExecStart = "${python}/bin/python3 ${./mcp_server.py}";
              LoadCredential = [
                "oidc-client-secret:${config.sops.secrets."second-brain.mcp.oidc_client_secret".path}"
              ];
              Restart = "on-failure";
              RestartSec = 10;
            };
          };

          # Funnel config lives in tailscaled's state; this unit (re)asserts it on every boot/deploy.
          systemd.services.second-brain-funnel = {
            description = "Publish the second-brain MCP server on Tailscale Funnel";
            after = [
              "tailscaled.service"
              "second-brain-mcp.service"
            ];
            requires = [ "tailscaled.service" ];
            wantedBy = [ "multi-user.target" ];
            path = [ config.services.tailscale.package ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${config.services.tailscale.package}/bin/tailscale funnel --bg --https=${toString cfg.mcp.funnelPort} http://127.0.0.1:${toString cfg.mcp.port}";
              ExecStop = "${config.services.tailscale.package}/bin/tailscale funnel --https=${toString cfg.mcp.funnelPort} off";
            };
          };
        })
      ];
    };
}
