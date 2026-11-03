{
  flake.nixosModules.services-selfheal =
    {
      config,
      lib,
      pkgs,
      inputs,
      flakeLib,
      ...
    }:
    let
      cfg = config.services.selfheal;
      stateDir = "/var/lib/selfheal";
      statusFile = "${stateDir}/status.json";
      worktreeDir = "/srv/selfheal/worktrees";
      monAddr = config.vars.network.containers.monitoring.localAddress;
      claude = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

      statusTool = pkgs.writeShellApplication {
        name = "selfheal-status";
        excludeShellChecks = [ "SC2016" ];
        runtimeInputs = [
          pkgs.jq
          pkgs.coreutils
          pkgs.util-linux
        ];
        text = ''
          f="''${SELFHEAL_STATUS:-${statusFile}}"
          now=$(date -u +%FT%TZ)

          write() {
            local tmp
            tmp=$(mktemp "$f.XXXXXX")
            if jq --arg now "$now" "$@" > "$tmp"; then
              chmod 0644 "$tmp"
              mv "$tmp" "$f"
            else
              rm -f "$tmp"
              return 1
            fi
          }

          locked() {
            exec 9>"$f.lock"
            flock 9
          }

          usage() {
            cat >&2 <<'EOF'
          usage: selfheal-status show
                 selfheal-status phase <diagnose|cluster|rediagnose|classify|act|digest>
                 selfheal-status clusters <total>
                 selfheal-status cluster <index> <title>
                 selfheal-status outcome <index> <no-issue|would-fix|would-escalate|pr-opened|escalated|skipped> <detail> [pr-url]
          EOF
            exit 64
          }

          cmd="''${1:-show}"
          [ "$#" -gt 0 ] && shift

          case "$cmd" in
            show)
              if [ -f "$f" ]; then jq . "$f"; else echo "no status file at $f" >&2; exit 1; fi
              ;;
            init)
              locked
              write -n --arg run "$1" --arg mode "$2" --argjson budget "$3" '{
                run_id: $run, mode: $mode, phase: "starting",
                started_at: $now, updated_at: $now, finished_at: null, result: null,
                cluster: {index: 0, total: 0, title: null, tool_calls: 0},
                tool_calls: {total: 0, budget_per_cluster: $budget},
                clusters: []
              }'
              ;;
            phase)
              [ "$#" -eq 1 ] || usage
              locked
              write --arg p "$1" '.phase = $p | .updated_at = $now' "$f"
              ;;
            clusters)
              [ "$#" -eq 1 ] || usage
              locked
              write --argjson n "$1" '.cluster.total = $n | .updated_at = $now' "$f"
              ;;
            cluster)
              [ "$#" -eq 2 ] || usage
              locked
              write --argjson i "$1" --arg t "$2" '
                .cluster.index = $i | .cluster.title = $t | .cluster.tool_calls = 0
                | .clusters = ([.clusters[] | select(.index != $i)] + [{index: $i, title: $t, outcome: "in-progress", detail: null, pr: null}] | sort_by(.index))
                | .updated_at = $now' "$f"
              ;;
            outcome)
              [ "$#" -ge 3 ] || usage
              case "$2" in
                no-issue|would-fix|would-escalate|pr-opened|escalated|skipped) ;;
                *) usage ;;
              esac
              locked
              write --argjson i "$1" --arg o "$2" --arg d "$3" --arg pr "''${4:-}" '
                .clusters = ([.clusters[] | select(.index != $i)]
                  + [((.clusters[] | select(.index == $i)) // {index: $i, title: null})
                     + {outcome: $o, detail: $d, pr: (if $pr == "" then null else $pr end)}]
                  | sort_by(.index))
                | .updated_at = $now' "$f"
              ;;
            tick)
              locked
              write '.tool_calls.total += 1
                | if .cluster.index > 0 then .cluster.tool_calls += 1 else . end
                | .updated_at = $now' "$f"
              if jq -e '.cluster.index > 0 and .cluster.tool_calls > .tool_calls.budget_per_cluster' "$f" >/dev/null; then
                i=$(jq -r .cluster.index "$f")
                echo "Tool-call budget for cluster $i is exhausted. This is escalation trigger 2: run selfheal-status outcome $i escalated (or would-escalate in dry run) with the reason, then move to the next cluster." >&2
                exit 2
              fi
              ;;
            finish)
              [ "$#" -eq 1 ] || usage
              locked
              write --arg r "$1" '.phase = "done" | .result = $r | .finished_at = $now | .updated_at = $now' "$f"
              ;;
            *)
              usage
              ;;
          esac
        '';
      };

      budgetHook = pkgs.writeShellApplication {
        name = "selfheal-budget-hook";
        excludeShellChecks = [ "SC2016" ];
        runtimeInputs = [
          pkgs.jq
          statusTool
        ];
        text = ''
          cmd=$(jq -r '.tool_input.command // ""')
          case "$cmd" in
            selfheal-status*) exit 0 ;;
          esac
          exec selfheal-status tick
        '';
      };

      lokiTool = pkgs.writeShellApplication {
        name = "selfheal-loki";
        excludeShellChecks = [ "SC2016" ];
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          if [ "$#" -lt 1 ]; then
            echo "usage: selfheal-loki '<logql>' [since, default 24h] [limit, default 200]" >&2
            exit 64
          fi
          curl -sS --fail --max-time 60 -G "http://${monAddr}:3100/loki/api/v1/query_range" \
            --data-urlencode "query=$1" \
            --data-urlencode "since=''${2:-24h}" \
            --data-urlencode "limit=''${3:-200}" \
            | jq -r '.data.result[] | .stream as $s | .values[] | "\(.[0] | tonumber / 1e9 | todate) \($s | to_entries | map("\(.key)=\(.value)") | join(",")) \(.[1])"'
        '';
      };

      promTool = pkgs.writeShellApplication {
        name = "selfheal-prom";
        excludeShellChecks = [ "SC2016" ];
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          if [ "$#" -lt 1 ]; then
            echo "usage: selfheal-prom '<promql>'   (instant query)" >&2
            echo "       selfheal-prom alerts        (currently firing Prometheus alerts)" >&2
            exit 64
          fi
          base="http://${monAddr}:9090/api/v1"
          if [ "$1" = alerts ]; then
            curl -sS --fail --max-time 60 "$base/alerts" | jq '.data.alerts'
          else
            curl -sS --fail --max-time 60 -G "$base/query" --data-urlencode "query=$1" | jq '.data.result'
          fi
        '';
      };

      gitCredential = pkgs.writeShellScript "selfheal-git-credential" ''
        [ "$1" = get ] || exit 0
        echo username=x-access-token
        printf 'password=%s\n' "$(cat "$CREDENTIALS_DIRECTORY/github_token")"
      '';

      gitHooks = pkgs.runCommand "selfheal-git-hooks" { } ''
        mkdir -p $out
        cp ${pkgs.writeShellScript "pre-push" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.git
              pkgs.coreutils
              pkgs.gnugrep
            ]
          }
          fail() {
            echo "selfheal pre-push: $*" >&2
            exit 1
          }
          while read -r _local_ref local_sha remote_ref _remote_sha; do
            case "$remote_ref" in
              refs/heads/selfheal/*) ;;
              *) fail "only refs/heads/selfheal/* may be pushed, got $remote_ref" ;;
            esac
            [ "$local_sha" = 0000000000000000000000000000000000000000 ] && fail "branch deletion is not allowed"
            files=$(git diff --name-only "origin/main...$local_sha")
            [ "$(printf '%s\n' "$files" | grep -c .)" -eq 1 ] || fail "a fix must touch exactly one file (escalation trigger 1): $files"
            case "$files" in
              modules/services/*|modules/containers/*) ;;
              *) fail "fixes outside modules/services and modules/containers must escalate: $files" ;;
            esac
            if printf '%s\n' "$files" | grep -Eiq 'disko|sops|secret|firewall|nftables|tailscale|network'; then
              fail "sensitive file, must escalate: $files"
            fi
            if git diff "origin/main...$local_sha" | grep -E '^[+-][^+-]' | grep -Eiq 'sops\.|secrets?\.|firewall|nftables|networking\.|allowed(TCP|UDP)Port|disko'; then
              fail "diff touches secrets or networking, must escalate"
            fi
          done
        ''} $out/pre-push
      '';

      basePrompt = pkgs.writeText "selfheal-prompt.md" ''
        You are the sutala self-heal agent, running headless on the NixOS host sutala as the
        unprivileged user `selfheal`. Your working directory is a fresh clone of
        github.com/${cfg.repo} reset to origin/main. Read CLAUDE.md and docs/INVENTORY.md
        first; they describe every host, service and the logs/metrics pipeline.

        Your job is to triage both nix-config-level issues (drift, misconfigurations evident
        from the repo) and running-system anomalies (failed units, alert-worthy metrics, log
        errors) on sutala, and end with one digest.

        Available tools on PATH:
        - `selfheal-loki '<logql>' [since] [limit]`: query Loki (all hosts' journald logs).
        - `selfheal-prom '<promql>'` and `selfheal-prom alerts`: query Prometheus.
        - `systemctl --failed`, `systemctl status <unit>`, `systemctl show <unit>`,
          `systemctl list-units`, `journalctl ...`: local systemd state (read only).
        - `nixos-version --configuration-revision` and read-only git (log, show, diff, status).
        - `selfheal-status ...`: progress file. Call it exactly as described below. Calls to it
          do not count against your tool budget.

        Pipeline. Follow it in order and keep the status file current:
        1. `selfheal-status phase diagnose`. Gather signals: failed units, firing alerts,
           error-level log lines over the last 24h, deployed revision vs origin/main.
        2. `selfheal-status phase cluster`. Group findings by root cause so one alert storm is
           one cluster. Order by impact. Work at most ${toString cfg.maxClusters} clusters;
           list the rest as `skipped`. Run `selfheal-status clusters <M>` with the count you
           will work. If there are no findings, run `selfheal-status clusters 0` and go to 4.
        3. For each cluster i (1-based):
           a. `selfheal-status cluster <i> '<short title>'`, then `selfheal-status phase rediagnose`.
              Re-validate against current live state. Never act on a signal from step 1 alone.
              If the problem is gone, record `no-issue` and move on.
           b. `selfheal-status phase classify`. The cluster must escalate if any one holds:
              1. the fix would span more than one file or module;
              2. root-cause investigation exceeds ${toString cfg.toolCallBudget} tool calls for this
                 cluster (enforced: tool calls are refused once the budget is spent);
              3. the fix touches a sensitive area: disko.nix, any secrets/sops config,
                 networking or firewall rules, or anything outside modules/services and
                 modules/containers.
              Escalation is a stop, not a pause: record it and move to the next cluster, with
              no partial fix attempt.
           c. `selfheal-status phase act`, then act per the mode section below and record the
              outcome with `selfheal-status outcome <i> <outcome> '<one-line detail>' [pr-url]`.
        4. `selfheal-status phase digest`. Your final message is the Telegram digest, posted
           verbatim. Plain text, no markdown, under 3000 characters. One line per cluster:
           number, title, outcome, and the evidence or PR link. Say "no issues found" when
           there were none.

        Hard rules: never change a running host's live state (no restarts, no writes outside
        your clone). Fixes ship only as pull requests; never merge. Never print or read
        credentials.
      '';

      dryRunPrompt = pkgs.writeText "selfheal-prompt-dry-run.md" ''
        Mode: DRY RUN. Diagnose and digest only. You cannot edit files, create branches,
        commit, push or open pull requests. In step 3c, record `would-fix` with the exact
        single-file change you would make (file path and the gist of the diff), or
        `would-escalate` with the trigger number and why.
      '';

      livePrompt = pkgs.writeText "selfheal-prompt-live.md" ''
        Mode: LIVE. In step 3c, for an auto-fixable cluster, work in a git worktree (the
        repo's git-safety hooks refuse pushes from the main checkout):
        1. `git worktree add ${worktreeDir}/<slug> -b selfheal/<yyyymmdd>-<slug> origin/main`
        2. `cd ${worktreeDir}/<slug>` and make the single-file change under modules/services
           or modules/containers.
        3. `nix fmt` then `nix flake check`. If either fails and the fix is not obvious within
           your budget, escalate instead.
        4. `git add <file>` and `git commit` with a short imperative message.
        5. `git push -u origin selfheal/<yyyymmdd>-<slug>` (a pre-push hook rejects anything
           that is not a single-file change in an allowed area; treat a rejection as an
           escalation).
        6. `gh pr create --draft` with a body stating the evidence, the change, and the
           Loki/Prometheus query that will show it worked once deployed.
        7. Record `pr-opened` with the PR URL and `cd ${cfg.repoDir}` before the next cluster.
        For an escalation record `escalated` with the trigger number and why; it is posted to
        Telegram as its own message.
      '';

      readOnlyTools = [
        "Read"
        "Grep"
        "Glob"
        "Bash(selfheal-status:*)"
        "Bash(selfheal-loki:*)"
        "Bash(selfheal-prom:*)"
        "Bash(systemctl --failed:*)"
        "Bash(systemctl status:*)"
        "Bash(systemctl show:*)"
        "Bash(systemctl list-units:*)"
        "Bash(systemctl list-timers:*)"
        "Bash(journalctl:*)"
        "Bash(nixos-version:*)"
        "Bash(git log:*)"
        "Bash(git show:*)"
        "Bash(git diff:*)"
        "Bash(git status:*)"
        "Bash(git rev-parse:*)"
      ];

      liveTools = [
        "Edit(/${worktreeDir}/*/modules/services/**)"
        "Edit(/${worktreeDir}/*/modules/containers/**)"
        "Write(/${worktreeDir}/*/modules/services/**)"
        "Write(/${worktreeDir}/*/modules/containers/**)"
        "Bash(git worktree add ${worktreeDir}/:*)"
        "Bash(cd ${worktreeDir}/:*)"
        "Bash(cd ${cfg.repoDir}:*)"
        "Bash(git add:*)"
        "Bash(git commit:*)"
        "Bash(git push -u origin selfheal/:*)"
        "Bash(gh pr create --draft:*)"
        "Bash(nix fmt:*)"
        "Bash(nix flake check:*)"
      ];

      deniedTools = [
        "WebFetch"
        "WebSearch"
        "Task"
        "Read(//run/credentials/**)"
        "Edit(/${cfg.repoDir}/**)"
        "Write(/${cfg.repoDir}/**)"
        "Edit(/${worktreeDir}/**/disko.nix)"
        "Edit(/${worktreeDir}/*/secrets/**)"
        "Write(/${worktreeDir}/*/secrets/**)"
        "Bash(gh pr merge:*)"
        "Bash(git push origin main:*)"
      ];

      claudeSettings = pkgs.writeText "selfheal-claude-settings.json" (
        builtins.toJSON {
          hooks.PreToolUse = [
            {
              matcher = "*";
              hooks = [
                {
                  type = "command";
                  command = lib.getExe budgetHook;
                }
              ];
            }
          ];
        }
      );

      streamFilter = ''
        if .type == "assistant" then
          (.message.content[]? |
            if .type == "text" then "say: " + .text
            elif .type == "tool_use" then "tool: " + .name + " " + ((.input.command // .input.file_path // .input.pattern // "") | tostring)
            else empty end)
        elif .type == "result" then "result: " + (.subtype // "") + " turns=" + ((.num_turns // 0) | tostring)
        else empty end
      '';

      runScript = pkgs.writeShellApplication {
        name = "selfheal-run";
        excludeShellChecks = [ "SC2016" ];
        runtimeInputs = [
          claude
          statusTool
          lokiTool
          promTool
          pkgs.git
          pkgs.gh
          pkgs.jq
          pkgs.curl
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          config.systemd.package
          config.nix.package
        ];
        text = ''
          state=${stateDir}
          repo=${cfg.repoDir}
          run_id=$(date -u +%Y%m%dT%H%M%SZ)
          rundir="$state/runs/$run_id"
          install -d -m 0750 "$state/runs"
          mkdir -p "$rundir"
          export SELFHEAL_STATUS=${statusFile}

          notify_file() {
            local token chat
            token=$(cat "$CREDENTIALS_DIRECTORY/bottoken")
            chat=$(cat "$CREDENTIALS_DIRECTORY/chatid")
            curl -sS --max-time 20 -o /dev/null -K - <<CURLCFG
          url = "https://api.telegram.org/bot$token/sendMessage"
          data = "chat_id=$chat"
          data = "message_thread_id=${toString cfg.telegramThreadId}"
          data-urlencode = "text@$1"
          CURLCFG
          }

          notify() {
            printf '%s\n' "$1" | head -c 3900 > "$rundir/notice.txt"
            notify_file "$rundir/notice.txt" || true
          }

          on_exit() {
            rc=$?
            if [ "$rc" -ne 0 ]; then
              selfheal-status finish "failed (exit $rc)" || true
              notify "Selfheal run $run_id failed (exit $rc). See: journalctl -u selfheal.service --invocation=0" || true
            fi
          }
          trap on_exit EXIT

          stamp="$state/first-run"
          [ -f "$stamp" ] || date -u +%s > "$stamp"
          days=$(( ($(date -u +%s) - $(cat "$stamp")) / 86400 ))
          mode=dry-run
          dry_run_forced=${lib.boolToString cfg.dryRun}
          if [ "$dry_run_forced" = false ] && [ "$days" -ge ${toString cfg.dryRunDays} ]; then
            mode=live
          fi
          echo "selfheal run $run_id mode=$mode (day $days of ${toString cfg.dryRunDays}-day dry run)"
          selfheal-status init "$run_id" "$mode" ${toString cfg.toolCallBudget}

          auth=(-c credential.helper= -c "credential.helper=${gitCredential}")
          if [ ! -d "$repo/.git" ]; then
            git "''${auth[@]}" clone "https://github.com/${cfg.repo}.git" "$repo"
          fi
          git -C "$repo" "''${auth[@]}" fetch --prune origin main
          git -C "$repo" checkout --force -B main origin/main
          git -C "$repo" reset --hard origin/main
          git -C "$repo" clean -ffdx
          rm -rf ${worktreeDir}
          git -C "$repo" worktree prune
          git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads \
            | grep -vx main | xargs -r git -C "$repo" branch -D
          git -C "$repo" config core.hooksPath ${gitHooks}
          git -C "$repo" config user.name selfheal
          git -C "$repo" config user.email selfheal@sutala.invalid

          allowed=(${lib.escapeShellArgs readOnlyTools})
          extra_args=()
          prompt_mode=${dryRunPrompt}
          if [ "$mode" = live ]; then
            allowed+=(${lib.escapeShellArgs liveTools})
            mkdir -p ${worktreeDir}
            extra_args=(--add-dir ${worktreeDir})
            prompt_mode=${livePrompt}
            git -C "$repo" config credential.helper ${gitCredential}
            GH_TOKEN=$(cat "$CREDENTIALS_DIRECTORY/github_token")
            export GH_TOKEN
          else
            git -C "$repo" config --unset-all credential.helper || true
          fi

          ANTHROPIC_API_KEY=$(cat "$CREDENTIALS_DIRECTORY/anthropic_api_key")
          export ANTHROPIC_API_KEY

          model_args=()
          ${lib.optionalString (cfg.model != null) "model_args=(--model ${lib.escapeShellArg cfg.model})"}

          cd "$repo"
          claude -p "$(cat ${basePrompt} "$prompt_mode")" \
            "''${model_args[@]}" \
            "''${extra_args[@]}" \
            --max-turns ${toString cfg.maxTurns} \
            --permission-mode dontAsk \
            --settings ${claudeSettings} \
            --allowedTools "''${allowed[@]}" \
            --disallowedTools ${lib.escapeShellArgs deniedTools} \
            --output-format stream-json --verbose \
            < /dev/null \
            | tee "$rundir/stream.jsonl" \
            | jq --unbuffered -r ${lib.escapeShellArg streamFilter} \
            || echo "claude exited non-zero; composing digest from the status file"

          result=$(jq -s 'map(select(.type == "result")) | last // {}' "$rundir/stream.jsonl")
          body=$(jq -r '.result // empty' <<<"$result")
          if [ -z "$body" ]; then
            body=$(jq -r '.clusters[]? | "\(.index). \(.title // "?"): \(.outcome) - \(.detail // "")"' ${statusFile})
            [ -n "$body" ] || body="Run ended before producing a digest ($(jq -r '.subtype // "no result"' <<<"$result"))."
          fi
          stats=$(jq -r --argjson r "$result" '"tool calls: \(.tool_calls.total), turns: \($r.num_turns // "?"), cost: $\($r.total_cost_usd // "?")"' ${statusFile})

          {
            printf 'Selfheal %s (%s)\n\n' "$run_id" "$mode"
            printf '%s\n\n' "$body"
            printf '%s\n' "$stats"
          } | head -c 3900 > "$rundir/digest.txt"

          selfheal-status finish "$(jq -r '.subtype // "unknown"' <<<"$result")"

          if [ "$mode" = live ]; then
            jq -r '.clusters[] | select(.outcome == "escalated") | "Selfheal escalation (\(.index). \(.title // "?")): \(.detail // "")"' ${statusFile} \
              | while IFS= read -r line; do notify "$line"; done
          fi
          notify_file "$rundir/digest.txt"

          find "$state/runs" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +
        '';
      };
    in
    {
      options.services.selfheal = {
        enable = lib.mkEnableOption "the daily headless Claude Code self-heal agent";

        dryRun = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Diagnose and digest only. Set to false to allow fix PRs once the dry-run period has elapsed.";
        };

        dryRunDays = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 7;
          description = "Minimum days since the first run before live mode can start, even with dryRun = false.";
        };

        toolCallBudget = lib.mkOption {
          type = lib.types.ints.positive;
          default = 20;
          description = "Tool calls allowed per cluster before it must escalate.";
        };

        maxClusters = lib.mkOption {
          type = lib.types.ints.positive;
          default = 5;
          description = "Clusters worked per run; the rest are listed as skipped.";
        };

        maxTurns = lib.mkOption {
          type = lib.types.ints.positive;
          default = cfg.toolCallBudget * cfg.maxClusters + 60;
          defaultText = lib.literalExpression "toolCallBudget * maxClusters + 60";
          description = "Hard cap on agent turns for a whole run.";
        };

        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Model passed to claude --model. null uses the CLI default.";
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 08:17:00";
          description = "systemd OnCalendar for the daily run, after the 06:00 (+1h jitter) auto-upgrade.";
        };

        timeout = lib.mkOption {
          type = lib.types.str;
          default = "2h";
          description = "TimeoutStartSec for one run.";
        };

        repo = lib.mkOption {
          type = lib.types.str;
          default = "kra3/nix-configs";
        };

        repoDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/selfheal/nix-configs";
        };

        telegramThreadId = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "message_thread_id of the Selfheal topic in the Sutala supergroup.";
        };
      };

      config = lib.mkIf cfg.enable {
        sops.secrets."selfheal.anthropic_api_key" = { };
        sops.secrets."selfheal.github_token" = { };
        sops.secrets."monitoring.grafana.telegram_bot_token" = { };
        sops.secrets."monitoring.grafana.telegram_chat_id" = { };

        environment.systemPackages = [
          statusTool
          lokiTool
          promTool
        ];

        systemd.tmpfiles.rules = [
          "d /srv/selfheal 0750 selfheal selfheal - -"
        ];

        systemd.services.selfheal = {
          description = "Self-heal agent: diagnose sutala and post a Telegram digest";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [ "/run/current-system/sw" ];
          environment = {
            HOME = stateDir;
            SELFHEAL_STATUS = statusFile;
            DISABLE_AUTOUPDATER = "1";
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
            DISABLE_TELEMETRY = "1";
          };
          serviceConfig = lib.mkMerge [
            {
              Type = "oneshot";
              User = "selfheal";
              Group = "selfheal";
              StateDirectory = "selfheal";
              StateDirectoryMode = "0755";
              UMask = "0022";
              TimeoutStartSec = cfg.timeout;
              LoadCredential = [
                "anthropic_api_key:${config.sops.secrets."selfheal.anthropic_api_key".path}"
                "github_token:${config.sops.secrets."selfheal.github_token".path}"
                "bottoken:${config.sops.secrets."monitoring.grafana.telegram_bot_token".path}"
                "chatid:${config.sops.secrets."monitoring.grafana.telegram_chat_id".path}"
              ];
              ExecStart = lib.getExe runScript;
            }
            (flakeLib.deployment-hardening.mkServiceSandbox {
              readWritePaths = [
                stateDir
                "/srv/selfheal"
                "/nix/var/nix/daemon-socket"
              ];
            })
          ];
        };

        systemd.timers.selfheal = {
          description = "Daily self-heal agent run";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.schedule;
            Persistent = true;
            RandomizedDelaySec = "10m";
          };
        };
      };
    };
}
