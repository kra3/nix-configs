# Takes the builders from this flake directly (not from a flakeLib specialArg), so another flake,
# e.g. a private work overlay, can import it as-is:
#   home-manager.users.<me>.imports = [ inputs.nix-configs.homeManagerModules.home-second-brain ];
{ config, ... }:
let
  sb = config.flake.lib.second-brain-packages;
in
{
  # Second brains on a user's own machine (the Macs): per brain, a vault the user edits in
  # Obsidian, synced with its hub repo by a background agent (launchd on macOS, a systemd user
  # timer on Linux) using the user's own ssh setup, plus a local MCP server for Claude Code in
  # ~/<claudeDir>. Nothing listens on the network.
  #
  # No host in this repo declares a work brain: a work overlay imports this module and sets e.g.
  #   programs.secondBrain.brains.work.sync = { enable = true; remote = "git@git.corp.example:me/brain.git"; };
  # A personal brain on a work machine is opt-in, and should be files only:
  #   programs.secondBrain.brains.home = { mcp.enable = false; sync = { enable = true; remote = "..."; }; };
  flake.homeManagerModules.home-second-brain =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.secondBrain;
      home = config.home.homeDirectory;
      syncScript = sb.mkSync pkgs;
      enabled = lib.filterAttrs (_: b: b.enable) cfg.brains;
      syncing = lib.filterAttrs (_: b: b.sync.enable) enabled;
      withMcp = lib.filterAttrs (_: b: b.mcp.enable) enabled;
      mcpFor =
        name: b:
        sb.mkMcp pkgs {
          inherit name;
          inherit (b) vaultDir;
        };
      obsidianFor =
        name: b:
        sb.mkObsidianConfig pkgs {
          inherit name;
          inherit (b) obsidian;
        };
      envFor =
        name: b:
        {
          VAULT_DIR = b.vaultDir;
          VAULT_GIT_DIR = b.gitDir;
          REMOTE = b.sync.remote;
          SYNC_HOST = cfg.hostLabel;
        }
        // lib.optionalAttrs (obsidianFor name b != null) {
          OBSIDIAN_MANAGED = "${obsidianFor name b}";
        };
    in
    {
      options.programs.secondBrain = {
        hostLabel = lib.mkOption {
          type = lib.types.str;
          default = "mac";
          description = "Names this machine in sync commits and conflict branches.";
        };
        brains = lib.mkOption {
          default = { };
          description = "Second brains on this machine, by name (e.g. home, work).";
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
                    default = "${home}/Brains/${name}";
                    description = "The vault folder Obsidian opens; a git work tree.";
                  };
                  gitDir = lib.mkOption {
                    type = lib.types.str;
                    default = "${config.vaultDir}.git";
                    defaultText = lib.literalExpression ''"''${vaultDir}.git"'';
                    description = "The vault's git dir, kept outside the vault.";
                  };
                  claudeDir = lib.mkOption {
                    type = lib.types.str;
                    default = "second-brain/${name}";
                    description = "Directory under $HOME where Claude Code gets this brain's tools.";
                  };
                  sync = {
                    enable = lib.mkEnableOption "two-way git sync with the hub repo";
                    remote = lib.mkOption {
                      type = lib.types.str;
                      example = "git@github.com:kra3/second-brain.git";
                      description = "Hub repo URL; uses this user's own ssh config, keys and agent.";
                    };
                    intervalSeconds = lib.mkOption {
                      type = lib.types.ints.positive;
                      default = 300;
                    };
                  };
                  obsidian = {
                    settings = lib.mkOption {
                      type = lib.types.attrsOf (pkgs.formats.json { }).type;
                      default = { };
                      example = {
                        appearance.cssTheme = "Catppuccin";
                        daily-notes.folder = "0 Inbox";
                      };
                      description = ''
                        Values for the vault's .obsidian/<name>.json files, merged in by every sync run:
                        these keys always win, everything else in the file stays as the app left it.
                        A name may include a folder, e.g. "plugins/obsidian-style-settings/data".
                      '';
                    };
                    themes = lib.mkOption {
                      type = lib.types.attrsOf lib.types.package;
                      default = { };
                      description = "Themes to install, by name: a folder with theme.css and manifest.json.";
                    };
                    plugins = lib.mkOption {
                      type = lib.types.attrsOf lib.types.package;
                      default = { };
                      description = "Community plugins to install and enable, by id: a folder with main.js and manifest.json.";
                    };
                  };
                  mcp.enable = lib.mkEnableOption "the local MCP server for Claude Code in ~/${config.claudeDir}" // {
                    default = true;
                  };
                };
              }
            )
          );
        };
      };

      config = lib.mkIf (enabled != { }) {
        home.packages = lib.mapAttrsToList mcpFor withMcp;

        home.file = lib.mkMerge (
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

        launchd.agents = lib.mkIf pkgs.stdenv.isDarwin (
          lib.mapAttrs' (
            name: b:
            lib.nameValuePair "second-brain-${name}-sync" {
              enable = true;
              config = {
                ProgramArguments = [ (lib.getExe syncScript) ];
                EnvironmentVariables = envFor name b;
                StartInterval = b.sync.intervalSeconds;
                RunAtLoad = true;
                ProcessType = "Background";
                StandardOutPath = "${home}/Library/Logs/second-brain-${name}-sync.log";
                StandardErrorPath = "${home}/Library/Logs/second-brain-${name}-sync.log";
              };
            }
          ) syncing
        );

        systemd.user.services = lib.mkIf pkgs.stdenv.isLinux (
          lib.mapAttrs' (
            name: b:
            lib.nameValuePair "second-brain-${name}-sync" {
              Unit.Description = "Two-way git sync of the ${name} second brain";
              Service = {
                Type = "oneshot";
                ExecStart = lib.getExe syncScript;
                Environment = lib.mapAttrsToList (k: v: "${k}=${v}") (envFor name b);
                SuccessExitStatus = [ 75 ];
              };
            }
          ) syncing
        );

        systemd.user.timers = lib.mkIf pkgs.stdenv.isLinux (
          lib.mapAttrs' (
            name: b:
            lib.nameValuePair "second-brain-${name}-sync" {
              Timer = {
                OnStartupSec = "2min";
                OnUnitActiveSec = "${toString b.sync.intervalSeconds}s";
              };
              Install.WantedBy = [ "timers.target" ];
            }
          ) syncing
        );
      };
    };
}
