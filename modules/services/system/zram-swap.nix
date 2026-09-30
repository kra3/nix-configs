{
  flake.nixosModules.services-system-zram-swap = {
    # sutala runs near-full RAM with no swap; gives the OOM killer headroom.
    zramSwap.enable = true;
  };
}
