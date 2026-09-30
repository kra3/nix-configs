{
  flake.nixosModules.services-system-zram-swap = {
    # sutala runs near-full RAM with no swap; gives the OOM killer headroom.
    zramSwap.enable = true;

    # Default swappiness (60) is tuned for slow disk swap; zram is cheap
    # RAM-backed compression, so the kernel should favor it over reclaiming
    # page cache well before memory pressure gets critical.
    boot.kernel.sysctl."vm.swappiness" = 100;
  };
}
