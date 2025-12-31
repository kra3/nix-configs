{ config, ... }:
{
  nix = {
    settings = { 
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    optimise.automatic = true;
  };

  system.autoUpgrade = {
    enable = true;
    dates = "*-*-* 06:00:00";
    randomizedDelaySec = "1h";
    flake = "github:kra3/nix-configs";
  };

  nixpkgs.config.allowUnfree = true;
}
