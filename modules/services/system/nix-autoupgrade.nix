{
  flake.nixosModules.services-system-nix-autoupgrade = {
    # Imported by the sutala host only (see nix-settings-split design) -- not by
    # any container, so no container.isContainer guard is needed here anymore.
    system.autoUpgrade = {
      enable = true;
      dates = "*-*-* 06:00:00";
      randomizedDelaySec = "1h";
      # Deploy from `release`, not `main`. `main` is an integration branch: CI and
      # the flake-update bot write to it freely, and nothing there reaches this
      # host until `release` is advanced deliberately.
      #
      # `release` must always contain this line. If it is ever pointed at a commit
      # that still says `.../nix-configs`, the next timer re-reads that and silently
      # reverts the host to tracking `main`.
      flake = "github:kra3/nix-configs/release";
    };
  };
}
