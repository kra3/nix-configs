{
  # sutala-specific: PCI/USB bus addresses below are tied to this board's topology
  # (Dell 0HMF7C, Comet Lake). Verified against `powertop --html` output 2026-09-05.
  flake.nixosModules.services-system-power-tuning = { lib, ... }:
  {
    # Batch dirty-page writeback instead of flushing every 5s (default 500 centisecs).
    boot.kernel.sysctl."vm.dirty_writeback_centisecs" = 1500;

    # Covers all 6 AHCI ports; host0/host3 already negotiate this via firmware default.
    boot.kernelParams = [ "libata.link_power_management_policy=med_power_with_dipm" ];

    # Runtime PM ("auto") for devices with no reliability history under it on this board.
    # Excluded: enp2s0 (active LAN NIC, PCI 02:00.0) -- Realtek runtime PM has a history
    # of link drops, and this is the only network path in/out of the house.
    services.udev.extraRules = ''
      # NVMe SSD (rpool)
      SUBSYSTEM=="pci", KERNEL=="0000:01:00.0", ATTR{power/control}="auto"
      # Host bridge / DRAM controller
      SUBSYSTEM=="pci", KERNEL=="0000:00:00.0", ATTR{power/control}="auto"
      # PCH thermal subsystem
      SUBSYSTEM=="pci", KERNEL=="0000:00:14.2", ATTR{power/control}="auto"
      # PCH USB (xHCI) controller
      SUBSYSTEM=="pci", KERNEL=="0000:00:14.0", ATTR{power/control}="auto"
      # LPC/eSPI bridge
      SUBSYSTEM=="pci", KERNEL=="0000:00:1f.0", ATTR{power/control}="auto"
      # AHCI controller itself
      SUBSYSTEM=="pci", KERNEL=="0000:00:17.0", ATTR{power/control}="auto"
      # enp4s0 (RTL8125 2.5GbE) -- unplugged, second port not in use
      SUBSYSTEM=="pci", KERNEL=="0000:04:00.0", ATTR{power/control}="auto"
      # wlp3s0 (Intel AX200 WiFi) -- unused, LAN-only setup
      SUBSYSTEM=="pci", KERNEL=="0000:03:00.0", ATTR{power/control}="auto"

      # WD My Passport (USB backup target, idVendor:idProduct 1058:0827) -- autosuspend
      # is safe since it's only active during scheduled backups.
      SUBSYSTEM=="usb", ATTR{idVendor}=="1058", ATTR{idProduct}=="0827", ATTR{power/control}="auto"
    '';
  };
}
