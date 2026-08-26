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
    flake = "github:kra3/nix-configs";
  };

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "intel-media-sdk-23.2.2"
    ];
  };
}
