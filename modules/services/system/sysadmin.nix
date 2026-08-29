{
  flake.nixosModules.services-system-sysadmin = { pkgs, ... }: {
    environment.systemPackages = [
      pkgs.htop
      pkgs.intel-gpu-tools
      pkgs.jq
      pkgs.lm_sensors
      pkgs.nvme-cli
      pkgs.powertop
      pkgs.ripgrep
      pkgs.smartmontools
    ];

    services.smartd.enable = true;
  };
}
