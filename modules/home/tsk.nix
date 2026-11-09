{
  flake.homeManagerModules.home-tsk =
    {
      inputs,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      herdr = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr;

      tsk = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.tsk;

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

      # tsk also writes config.toml (backup, board settings), so only this marked block is ours.
      agents = pkgs.writeText "tsk-agents.toml" ''
        # BEGIN nix-managed agents
        [agent.scout]
        command = ["claude", "--permission-mode", "auto", "--model", "claude-haiku-5-5", "--effort", "low"]
        prompt_append = "Research only: write findings into the task notes with tsk and change no code."

        [agent.builder]
        command = ["claude", "--permission-mode", "auto", "--model", "claude-sonnet-5-5", "--effort", "medium"]
        prompt_append = "Implement exactly the task's steps and run its acceptance check. If anything is unclear, block the task instead of guessing."

        [agent.claude]
        command = ["claude", "--permission-mode", "auto", "--model", "claude-opus-5-5", "--effort", "high"]
        # END nix-managed agents
      '';

      maxStarted = 1;
      triagePrompt = "Triage tsk task T$n. Read it with 'tsk list $n'. If it lacks concrete steps or an acceptance check and you can infer them, add them. If it is not work an agent can do in a git repo (an errand, a call, a decision only the user can make), assign me instead. Otherwise assign exactly one profile with 'tsk edit $n --assignee <profile>': scout for research or a question with no code change, builder when it has concrete steps and a check, claude when it is vague, design or debugging. Do not change its status.";
      runner = pkgs.writeShellApplication {
        name = "tsk-runner";
        runtimeInputs = [
          tsk
          herdr
          pkgs.jq
          pkgs.git
          pkgs.coreutils
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
        ];
        text = ''
          herdr workspace list >/dev/null 2>&1 || exit 0
          tasks=$(tsk list --all --json)
          started=$(jq '[.[] | select(.status == "started")] | length' <<<"$tasks")
          (( started < ${toString maxStarted} )) || exit 0
          for n in $(jq -r '.[] | select(.status == "ready" and .project != null and .assignee == null) | .number' <<<"$tasks"); do
            timeout 300 claude -p --model claude-haiku-5-5 --effort low \
              --allowedTools='Bash(tsk list *),Bash(tsk edit *),Bash(tsk steps *)' \
              "${triagePrompt}" || true
          done
          tasks=$(tsk list --all --json)
          for n in $(jq -r '.[] | select(.status == "ready" and .project != null and .assignee != null and .assignee_kind != "person") | .number' <<<"$tasks"); do
            # tsk only checks HERDR_ENV; herdr itself reaches the server over its default socket.
            if HERDR_ENV=1 tsk dispatch "$n"; then exit 0; fi
          done
        '';
      };
    in
    {
      home.packages = [
        tsk
        runner
      ];

      systemd.user.services.tsk-runner = lib.mkIf pkgs.stdenv.isLinux {
        Unit.Description = "Dispatch the next ready tsk task";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe runner;
          # tsk dispatch leaves a detached helper that names the herdr agent; don't kill it on exit.
          KillMode = "process";
          TimeoutStartSec = "30min";
        };
      };

      systemd.user.timers.tsk-runner = lib.mkIf pkgs.stdenv.isLinux {
        Timer.OnCalendar = "*:0/15";
        Install.WantedBy = [ "timers.target" ];
      };

      launchd.agents.tsk-runner = lib.mkIf pkgs.stdenv.isDarwin {
        enable = true;
        config = {
          ProgramArguments = [ (lib.getExe runner) ];
          StartInterval = 900;
          ProcessType = "Background";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/tsk-runner.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/tsk-runner.log";
        };
      };

      home.file.".claude/skills/tsk-cli/SKILL.md".source = "${tsk.src}/skills/tsk-cli/SKILL.md";

      home.activation.tskAgents = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        f=$HOME/.tsk/config.toml
        run mkdir -p "$HOME/.tsk"
        [ -e "$f" ] || run install -m600 /dev/null "$f"
        rest=$(sed '/^# BEGIN nix-managed agents$/,/^# END nix-managed agents$/d' "$f")
        [ -n "''${DRY_RUN:-}" ] || (umask 077; printf '%s\n' "$rest" | cat - ${agents} >"$f.tmp" && mv "$f.tmp" "$f")
      '';

      # herdr rewrites its plugin registry at runtime, so register the plugin at activation; re-linking picks up new store paths.
      home.activation.herdrTskPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${herdr}/bin/herdr plugin unlink herdr-tsk >/dev/null 2>&1 || true
        run ${herdr}/bin/herdr plugin link ${plugin} --enabled
      '';
    };
}
