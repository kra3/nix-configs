{ lib, ... }:
{
  # Healthcheck for the common "wget the app's local HTTP endpoint" pattern.
  mkHealthCheck =
    { port, path ? "ping", startPeriod ? "30s" }:
    {
      healthCmd = "wget -qO- http://localhost:${toString port}/${path}";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
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
}
