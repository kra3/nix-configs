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
        home.activation.ollamaPullModels = lib.mkIf (cfg.models != [ ]) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if ${ollamaBin} list >/dev/null 2>&1; then
              present="$(${ollamaBin} list 2>/dev/null)"
              for m in ${lib.concatStringsSep " " cfg.models}; do
                if ! printf '%s\n' "$present" | grep -q "$m"; then
                  run ${ollamaBin} pull "$m" || echo "⚠️  ollama pull $m failed"
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
