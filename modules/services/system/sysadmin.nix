{
  flake.nixosModules.services-system-sysadmin = { pkgs, ... }: {
    environment.systemPackages = [
      pkgs.htop
      pkgs.jq
      pkgs.nvme-cli
      pkgs.powertop
      pkgs.ripgrep
      pkgs.smartmontools
    ];

    services.smartd.enable = true;
  };
}
