{ lib, ... }:
{
  flake.lib.quadlet = {
    # Healthcheck for the common "wget the app's local HTTP endpoint" pattern.
    mkHealthCheck =
      {
        port,
        path ? "ping",
        startPeriod ? "60s",
      }:
      {
        # Retries internally so podman's immediate first probe (before the app's port is up) doesn't fail nixos-rebuild switch.
        healthCmd = "i=0; while [ $i -lt 12 ]; do wget -qO- http://localhost:${toString port}/${path} && exit 0; sleep 2; i=$((i+1)); done; exit 1";
        healthOnFailure = "kill";
        healthInterval = "60s";
        healthTimeout = "55s";
        healthRetries = 3;
        healthStartPeriod = startPeriod;
      };

    # Unit wiring shared by quadlet containers: wait for their network(s), restart on exit.
    mkNetworkDeps =
      {
        networkServices,
        extraAfter ? [ ],
        extraRequires ? [ ],
        bindsTo ? [ ],
        restart ? "always",
      }:
      {
        unitConfig = {
          After = networkServices ++ extraAfter;
          Requires = networkServices ++ extraRequires;
        }
        // lib.optionalAttrs (bindsTo != [ ]) { BindsTo = bindsTo; };
        serviceConfig.Restart = restart;
      };
  };
}
