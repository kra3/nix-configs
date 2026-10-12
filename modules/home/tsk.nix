{
  flake.homeManagerModules.home-tsk =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      herdr = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr;

      tsk = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "tsk";
        version = "0.11.6";

        src = pkgs.fetchFromGitHub {
          owner = "smarzban";
          repo = "tsk";
          tag = "v${finalAttrs.version}";
          hash = "sha256-nkuCSQg6C1EVVYTdXdLDZV+TT0Xdu93kTV/LgBJEwGQ=";
        };

        cargoHash = "sha256-FMCxgtHvra3AYwL0M2s8x5XbYaLXRGRk1oZ8ezq51Js=";
        doCheck = false;

        meta.mainProgram = "tsk";
      });

      # The repo manifest builds with cargo and runs ./target/release/tsk; point both at the Nix binary instead.
      plugin = pkgs.runCommand "herdr-tsk-plugin" { } ''
        mkdir -p $out/scripts
        install -m755 ${tsk.src}/scripts/open-board.sh ${tsk.src}/scripts/open-capture.sh $out/scripts/
        substituteInPlace $out/scripts/open-board.sh \
          --replace-fail 'plugin_bin="''${TSK_BIN:-$script_dir/../target/release/tsk}"' 'plugin_bin=${tsk}/bin/tsk'
        cat > $out/herdr-plugin.toml <<'EOF'
        id = "herdr-tsk"
        name = "herdr-tsk"
        version = "${tsk.version}"
        min_herdr_version = "0.9.0"
        platforms = ["linux", "macos"]

        [[panes]]
        id = "board"
        title = "tsk"
        placement = "split"
        command = ["${tsk}/bin/tsk"]

        [[actions]]
        id = "open-board"
        title = "Open tsk board"
        command = ["bash", "scripts/open-board.sh"]

        [[actions]]
        id = "quick-capture"
        title = "Quick capture"
        command = ["bash", "scripts/open-capture.sh"]
        EOF
      '';
    in
    {
      home.packages = [ tsk ];

      home.file.".claude/skills/tsk-cli/SKILL.md".source = "${tsk.src}/skills/tsk-cli/SKILL.md";

      # herdr rewrites its plugin registry at runtime, so register the plugin at activation; re-linking picks up new store paths.
      home.activation.herdrTskPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${herdr}/bin/herdr plugin unlink herdr-tsk >/dev/null 2>&1 || true
        run ${herdr}/bin/herdr plugin link ${plugin} --enabled
      '';
    };
}
