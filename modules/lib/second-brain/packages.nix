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
          pkgs.jq
          pkgs.diffutils
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

    # Obsidian theme and plugin files pinned by hash, to hand to a brain's `obsidian.themes` /
    # `obsidian.plugins` options. Release assets are used as published, not rebuilt.
    obsidianAssets =
      pkgs:
      let
        ctpRev = "5f36251340fb442b94492f4ec7d8e5093e0b50ad";
        ssVersion = "1.0.9";
        ctp = file: "https://raw.githubusercontent.com/catppuccin/obsidian/${ctpRev}/${file}";
        ss =
          file: "https://github.com/mgmeyers/obsidian-style-settings/releases/download/${ssVersion}/${file}";
      in
      {
        # The Catppuccin theme (v0.4.52). Flavour and accent are Style Settings values.
        catppuccin = pkgs.linkFarm "obsidian-catppuccin-0.4.52" [
          {
            name = "theme.css";
            path = pkgs.fetchurl {
              url = ctp "theme.css";
              hash = "sha256-bBMwcArgB39cedlQqQF5pC53eHIp3hJ25cvloEjlcu0=";
            };
          }
          {
            name = "manifest.json";
            path = pkgs.fetchurl {
              url = ctp "manifest.json";
              hash = "sha256-vjbS8zhQZ1NPowSQZ7GXqKjZBfpk5ypIOHvRWQw4JHk=";
            };
          }
        ];
        # Style Settings: the plugin that exposes the theme's flavour and accent.
        styleSettings = pkgs.linkFarm "obsidian-style-settings-${ssVersion}" [
          {
            name = "main.js";
            path = pkgs.fetchurl {
              url = ss "main.js";
              hash = "sha256-GCirqs2rTFV4twWmJcWFswUS+O+tTHz8WhjnDMNVdGg=";
            };
          }
          {
            name = "manifest.json";
            path = pkgs.fetchurl {
              url = ss "manifest.json";
              hash = "sha256-nP/cIM8qoTVIIOAFC2lLD5tXZEbj1dRKNq6LAYflv7g=";
            };
          }
          {
            name = "styles.css";
            path = pkgs.fetchurl {
              url = ss "styles.css";
              hash = "sha256-7nk30r5QZTqJzLMK5fBXKyNQfVt/EyjQBScaNjB1v9g=";
            };
          }
        ];
      };

    # What a brain's `obsidian` option manages inside <vault>/.obsidian, as one store path that
    # sync.sh applies (OBSIDIAN_MANAGED): settings/<file>.json fragments merged into the vault's
    # JSON (managed keys win, the rest stays yours), themes/<name>/ and plugins/<id>/ copied in.
    # Null when nothing is declared.
    mkObsidianConfig =
      pkgs:
      {
        name,
        obsidian,
      }:
      let
        json = pkgs.formats.json { };
        settings =
          obsidian.settings
          // pkgs.lib.optionalAttrs (obsidian.plugins != { }) {
            # Array: sync.sh unions it with what the vault already enables.
            "community-plugins" = builtins.attrNames obsidian.plugins;
          };
      in
      if settings == { } && obsidian.themes == { } && obsidian.plugins == { } then
        null
      else
        pkgs.runCommand "second-brain-obsidian-${name}" { } (
          ''
            mkdir -p $out/settings $out/themes $out/plugins
          ''
          + pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (f: v: ''
              mkdir -p "$(dirname "$out/settings/${f}.json")"
              ln -s ${json.generate "${baseNameOf f}.json" v} "$out/settings/${f}.json"
            '') settings
          )
          + pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (n: p: ''
              ln -s ${p} "$out/themes/"${pkgs.lib.escapeShellArg n}
            '') obsidian.themes
          )
          + pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (n: p: ''
              ln -s ${p} "$out/plugins/"${pkgs.lib.escapeShellArg n}
            '') obsidian.plugins
          )
        );

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
