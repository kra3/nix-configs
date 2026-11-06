{
  # Builders shared by the sutala system module (services-second-brain-default) and the
  # Home Manager module for the Macs (home-second-brain). One brain = one vault + one hub repo.
  flake.lib.second-brain-packages = {
    # Two-way git sync of one vault (sync.sh). Env: VAULT_DIR, VAULT_GIT_DIR, REMOTE, SYNC_HOST.
    mkSync =
      pkgs:
      pkgs.writeShellApplication {
        name = "second-brain-sync";
        # On macOS, ssh stays the system one (keychain, VPN-specific config); git finds it on PATH.
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.findutils
        ]
        ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.openssh;
        text = builtins.readFile ./sync.sh;
      };

    # Local stdio MCP server for one vault, started by Claude Code from <claudeDir>/.mcp.json.
    mkMcp =
      pkgs:
      { name, vaultDir }:
      let
        # Stable: unstable's fastmcp is marked broken against mcp 2.x.
        python = pkgs.python3.withPackages (ps: [ ps.fastmcp ]);
      in
      pkgs.writeShellApplication {
        name = "second-brain-mcp-${name}";
        text = ''
          export VAULT_DIR=${pkgs.lib.escapeShellArg vaultDir}
          exec ${python}/bin/python3 ${./mcp_server.py}
        '';
      };

    # The files that make <claudeDir> a Claude Code project for one brain.
    claudeDirFiles =
      {
        name,
        vaultDir,
        mcp,
      }:
      {
        ".mcp.json".text = builtins.toJSON {
          mcpServers."second-brain".command = "${mcp}/bin/second-brain-mcp-${name}";
        };
        # Trust this one server and let Claude edit the vault outside the cwd.
        ".claude/settings.json".text = builtins.toJSON {
          enabledMcpjsonServers = [ "second-brain" ];
          permissions.additionalDirectories = [ vaultDir ];
        };
        "CLAUDE.md".text = ''
          # Second brain: ${name}

          The vault is `${vaultDir}` (a git work tree; a background job commits and pushes it
          every few minutes, so never run git in it yourself). Read `${vaultDir}/CLAUDE.md`
          before doing anything: it holds the folder rules, the weekly review and the rule
          that evergreen notes are written by the owner, not by Claude.

          Use the `second-brain` MCP tools (capture, search_notes, list_tasks, recent_changes,
          orphans, backlinks, ...) or edit the files directly.
        '';
      };
  };
}
