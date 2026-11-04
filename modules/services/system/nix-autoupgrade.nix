{
  flake.nixosModules.services-system-nix-autoupgrade =
    { config, ... }:
    {
      # Imported by the sutala host only (see nix-settings-split design) -- not by
      # any container, so no container.isContainer guard is needed here anymore.
      system.autoUpgrade = {
        enable = true;
        dates = "*-*-* 06:00:00";
        randomizedDelaySec = "1h";
        # Deploy from the `deploy` branch, not `main`: it only advances via the
        # promote-deploy workflow (green CI + optional environment approval), so
        # landing a commit on main alone does not yield root on the hosts.
        flake = "github:kra3/nix-configs/${config.vars.deployRef}";
      };
    };
}
