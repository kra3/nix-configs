{
  flake.homeManagerModules.home-claude-code =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    {
      programs.git.settings.hook.review-gate = {
        event = "pre-push";
        command = "$HOME/.claude/hooks/review-gate.sh";
      };

      home.packages = [
        inputs.llm-agents.packages.${pkgs.system}.claude-code
        pkgs.sox # audio I/O for Claude Code voice mode
        pkgs.nodejs # required by some Claude Code plugin hooks (e.g. i-have-adhd, ponytail)
      ];

      # settings.json is live-mutated (/config, plugin installs), so settings.base.json is
      # merged into it on switch: objects recurse, arrays union, base wins scalars. Removals don't propagate.
      # RTK.md is excluded: mutated by `rtk init`.
      home.activation.claudeSettingsMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        f="$HOME/.claude/settings.json"
        base=${./claude-code/settings.base.json}
        run mkdir -p "$HOME/.claude"
        if [ ! -s "$f" ]; then
          run install -m 600 "$base" "$f"
        elif merged=$(${pkgs.jq}/bin/jq -s '
            def m($a; $b):
              if ($a | type) == "object" and ($b | type) == "object" then
                reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = m($a[$k]; $b[$k]))
              elif ($a | type) == "array" and ($b | type) == "array" then $a + ($b - $a)
              else $b end;
            m(.[0]; .[1])' "$f" "$base") \
          && [ "$merged" != "$(${pkgs.jq}/bin/jq . "$f")" ]; then
          run cp "$f" "$f.bak"
          printf '%s\n' "$merged" > "$f.tmp" && run mv "$f.tmp" "$f"
        fi
      '';

      home.file = {
        ".claude/CLAUDE.md" = {
          source = ./claude-code/CLAUDE.md;
          force = true;
        };
        ".claude/statusline.sh" = {
          source = ./claude-code/statusline.sh;
          force = true;
        };
        ".claude/hooks/guard-bash.sh" = {
          source = ./claude-code/hooks/guard-bash.sh;
          executable = true;
          force = true;
        };
        ".claude/hooks/ask-main-merge.sh" = {
          source = ./claude-code/hooks/ask-main-merge.sh;
          executable = true;
          force = true;
        };
        ".claude/hooks/review-gate.sh" = {
          source = ./claude-code/hooks/review-gate.sh;
          executable = true;
          force = true;
        };
        ".claude/hooks/notify.sh" = {
          source = ./claude-code/hooks/notify.sh;
          executable = true;
          force = true;
        };
        ".claude/.i-have-adhd-always".text = "";
      };
    };
}
