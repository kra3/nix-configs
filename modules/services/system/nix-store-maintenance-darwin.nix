{
  # nix-darwin removed nix.gc.dates outright (mkRemovedOptionModule, "Use
  # nix.gc.interval instead") -- unlike NixOS, this is a hard eval error, not
  # a silent no-op. interval's own default (weekly, Sunday 03:15) is already
  # sensible, so it's left unset here rather than duplicated.
  nix.settings.auto-optimise-store = true;

  nix.gc = {
    automatic = true;
    options = "--delete-older-than 7d";
  };

  nix.optimise.automatic = true;
}
