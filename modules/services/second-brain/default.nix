{
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
      user = "second-brain";
      baseDir = "/srv/appdata/second-brain";
      stateDir = "${baseDir}/state";
      gitDir = "${baseDir}/vault.git";
      obConfigHome = "${stateDir}/config";
      publicUrl = "https://${cfg.mcp.publicHost}:${toString cfg.mcp.funnelPort}";

      # obsidian-headless (unfree EULA) only exists on unstable.
      unstable = import inputs.nixpkgs-unstable {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfreePredicate = drv: lib.getName drv == "obsidian-headless";
      };
      obsidianHeadless = unstable.obsidian-headless;
      # Stable: unstable's fastmcp is marked broken against mcp 2.x.
      python = pkgs.python3.withPackages (ps: [ ps.fastmcp ]);

      sandbox = flakeLib.deployment-hardening.mkServiceSandbox {
        readWritePaths = [ baseDir ];
      };
      common = sandbox // {
        User = user;
        Group = user;
        UMask = "0007";
        # Hides other users' processes, e.g. sync-setup's --password argument.
        ProtectProc = "invisible";
      };

      git = "${pkgs.git}/bin/git --git-dir=${gitDir} --work-tree=${cfg.vaultDir}";
    in
    {
      options.services.secondBrain = {
        vaultDir = lib.mkOption {
          type = lib.types.str;
          default = "${baseDir}/vault";
          description = "Live copy of the Obsidian vault, kept current by headless Obsidian Sync.";
        };

        sync = {
          enable = lib.mkEnableOption "headless Obsidian Sync of the vault";
          vaultName = lib.mkOption {
            type = lib.types.str;
            description = "Remote vault name as shown by `ob sync-list-remote`.";
          };
          deviceName = lib.mkOption {
            type = lib.types.str;
            default = config.networking.hostName;
          };
          endToEndEncrypted = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Remote vault uses end-to-end encryption (needs the vault password secret).";
          };
        };

        snapshot = {
          enable = lib.mkEnableOption "hourly git snapshots of the vault (history kept locally in ${gitDir})";
          remote = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "git@github.com:kra3/second-brain.git";
            description = "SSH remote to push snapshots to; null keeps history on this host only.";
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
          port = lib.mkOption {
            type = lib.types.port;
            default = 8765;
            description = "Loopback port of the MCP server; only Funnel reaches it.";
          };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.sync.enable || cfg.snapshot.enable || cfg.mcp.enable) {
          users.users.${user} = {
            isSystemUser = true;
            group = user;
            home = stateDir;
          };
          users.groups.${user} = { };
          # Lets kra3 browse the server copy; edits still belong on a synced device.
          users.users.kra3.extraGroups = [ user ];

          systemd.tmpfiles.rules = [
            "d ${baseDir} 0750 ${user} ${user} - -"
            "d ${cfg.vaultDir} 2770 ${user} ${user} - -"
            "d ${stateDir} 0700 ${user} ${user} - -"
          ];
        })

        (lib.mkIf cfg.sync.enable {
          sops.secrets = {
            "second-brain.obsidian.auth_token" = { };
          }
          // lib.optionalAttrs cfg.sync.endToEndEncrypted {
            "second-brain.obsidian.vault_password" = { };
          };

          systemd.services.second-brain-sync = {
            description = "Headless Obsidian Sync of the second-brain vault";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [
              obsidianHeadless
              pkgs.jq
            ];
            environment.XDG_CONFIG_HOME = obConfigHome;
            # The vault link lives in ob's own state; set it up once, idempotently, then follow changes.
            script = ''
              OBSIDIAN_AUTH_TOKEN="$(< "$CREDENTIALS_DIRECTORY/auth-token")"
              export OBSIDIAN_AUTH_TOKEN
              linked=0
              for f in "$XDG_CONFIG_HOME"/obsidian-headless/sync/*/config.json; do
                [ -e "$f" ] || continue
                if jq -e --arg p ${lib.escapeShellArg cfg.vaultDir} '.vaultPath == $p' "$f" >/dev/null; then
                  linked=1
                fi
              done
              if [ "$linked" = 0 ]; then
                echo "linking ${cfg.vaultDir} to remote vault ${cfg.sync.vaultName}"
                ob sync-setup \
                  --vault ${lib.escapeShellArg cfg.sync.vaultName} \
                  --path ${lib.escapeShellArg cfg.vaultDir} \
                  --device-name ${lib.escapeShellArg cfg.sync.deviceName} \
                  ${lib.optionalString cfg.sync.endToEndEncrypted ''--password "$(< "$CREDENTIALS_DIRECTORY/vault-password")"''}
              fi
              exec ob sync --path ${lib.escapeShellArg cfg.vaultDir} --continuous
            '';
            serviceConfig = common // {
              LoadCredential = [
                "auth-token:${config.sops.secrets."second-brain.obsidian.auth_token".path}"
              ]
              ++ lib.optional cfg.sync.endToEndEncrypted "vault-password:${
                config.sops.secrets."second-brain.obsidian.vault_password".path
              }";
              Restart = "always";
              RestartSec = 30;
            };
          };
        })

        (lib.mkIf cfg.snapshot.enable {
          sops.secrets = lib.optionalAttrs (cfg.snapshot.remote != null) {
            "second-brain.git.deploy_key" = { };
          };

          programs.ssh.knownHosts = lib.optionalAttrs (cfg.snapshot.remote != null) {
            "github.com".publicKey =
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
          };

          systemd.services.second-brain-snapshot = {
            description = "Commit the second-brain vault to git${
              lib.optionalString (cfg.snapshot.remote != null) " and push it"
            }";
            wants = lib.optional (cfg.snapshot.remote != null) "network-online.target";
            after = lib.optional (cfg.snapshot.remote != null) "network-online.target";
            path = [ pkgs.openssh ];
            # The git dir sits outside the vault so Obsidian Sync never sees it.
            script = ''
              if [ ! -d ${gitDir} ]; then
                ${git} init --quiet --initial-branch=main
                printf '%s\n' '.obsidian/workspace*.json' '.trash/' '.mcp-*.tmp' > ${gitDir}/info/exclude
              fi
              ${git} add --all
              if ! ${git} diff --cached --quiet; then
                ${git} -c user.name=second-brain -c user.email=second-brain@${config.networking.hostName} \
                  commit --quiet -m "snapshot $(date --iso-8601=minutes)"
              fi
              ${lib.optionalString (cfg.snapshot.remote != null) ''
                GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/deploy-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
                export GIT_SSH_COMMAND
                ${git} push --quiet ${lib.escapeShellArg cfg.snapshot.remote} HEAD:main
              ''}
            '';
            serviceConfig = common // {
              Type = "oneshot";
              LoadCredential =
                lib.optional (cfg.snapshot.remote != null)
                  "deploy-key:${config.sops.secrets."second-brain.git.deploy_key".path}";
            };
          };

          systemd.timers.second-brain-snapshot = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "hourly";
              Persistent = true;
              RandomizedDelaySec = "5m";
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
