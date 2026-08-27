{
  flake.darwinModules.services-system-nix-defaults-darwin = {
    # nix-darwin removed nix.gc.dates outright (mkRemovedOptionModule, "Use
    # nix.gc.interval instead") -- unlike NixOS, this is a hard eval error, not
    # a silent no-op. interval's own default (weekly, Sunday 03:15) is already
    # sensible, so it's left unset here rather than duplicated. Confirmed
    # against the actual nix-darwin module source, and confirmed that a single
    # file guarding nix.gc.dates behind lib.mkIf pkgs.stdenv.isLinux still
    # trips the removed-option check on darwin (mkIf's laziness only gates the
    # value, not whether the option was touched at all) -- so this has to stay
    # a separate file, not a platform-conditional branch inside one shared file.
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };

    nix.gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };

    nix.optimise.automatic = true;
  };
}
