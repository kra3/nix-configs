{ lib, config, ... }:
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    optimise.automatic = true;
  };

  # Only the host auto-upgrades. Containers import this module too, and inside a
  # container the generated unit resolves nixosConfigurations.$(hostname) --
  # "monitoring" / "media-play" / "home-auto", none of which the flake exposes --
  # so every container upgrade failed at flake resolution.
  system.autoUpgrade = lib.mkIf (!config.boot.isContainer) {
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

  nixpkgs.config.allowUnfree = true;
}
