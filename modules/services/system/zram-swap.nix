{
  flake.nixosModules.services-system-zram-swap = {
    # sutala runs near-full RAM with no swap; gives the OOM killer headroom.
    zramSwap.enable = true;

    # Default (60) assumes slow disk swap; zram is cheap, so favor it more.
    boot.kernel.sysctl."vm.swappiness" = 100;
  };
}
