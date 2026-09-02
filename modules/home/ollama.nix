{
  flake.homeManagerModules.home-ollama =
    { config, lib, pkgs, ... }:
    let
      cfg = config.local.ollama;
      ollamaBin = "${config.services.ollama.package}/bin/ollama";
    in
    {
      # Cross-platform ollama (systemd on Linux, launchd on darwin, both via
      # services.ollama). Imported directly where wanted, not via home-profiles-ai.
      options.local.ollama.models = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "qwen2.5-coder:14b" ];
        description = "Models to keep pulled (services.ollama has no loadModels).";
      };

      config = {
        services.ollama.enable = true; # acceleration=null → Metal on aarch64-darwin
        home.packages = [ config.services.ollama.package ];

        # Reconcile declared models; skip quietly if the server isn't up yet.
        # Pulls run backgrounded so a missing/large model doesn't block the switch,
        # and presence is checked per-model via `ollama show` (exact match, no
        # substring/regex risk from grep'ing `ollama list` output).
        home.activation.ollamaPullModels = lib.mkIf (cfg.models != [ ]) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if ${ollamaBin} list >/dev/null 2>&1; then
              for m in ${lib.escapeShellArgs cfg.models}; do
                if ! ${ollamaBin} show "$m" >/dev/null 2>&1; then
                  ( run ${ollamaBin} pull "$m" || echo "⚠️  ollama pull $m failed" ) >>/tmp/ollama-pull-activation.log 2>&1 &
                  disown
                fi
              done
            else
              echo "ℹ️  ollama server not reachable during activation — skipping model reconcile."
            fi
          ''
        );
      };
    };
}
