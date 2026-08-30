{
  flake.nixosModules.services-system-nix-autoupgrade = {
    # Imported by the sutala host only (see nix-settings-split design) -- not by
    # any container, so no container.isContainer guard is needed here anymore.
    system.autoUpgrade = {
      enable = true;
      dates = "*-*-* 06:00:00";
      randomizedDelaySec = "1h";
      # Deploy from `main`. `main` is protected (PRs + required checks), so every
      # commit that lands here has already passed CI -- no separate release
      # branch is needed as a gate.
      flake = "github:kra3/nix-configs/main";
    };
  };
}
