{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager

    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nix.nix
    ../../modules/acme.nix
    ../../modules/nginx.nix
    ../../modules/openssh.nix
    ../../modules/sops.nix
    ../../modules/technitium.nix
    ../../modules/fail2ban.nix
    ../../modules/vim.nix
    ../../modules/users/root.nix
    ../../modules/users/kra3.nix
  ];

  networking.hostName = "sutala";
  networking.hostId = "d2a81622";
  networking.enableIPv6 = false;
  networking.firewall.enable = true;
  networking.nftables.enable = true;

  time.timeZone = "UTC";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelParams = [
    "zfs.zfs_arc_max=3338665984"
    "ipv6.disable=1"
  ];
  boot.zfs.extraPools = [ "tank" ];

  services.zfs = {
    autoScrub = {
      enable = true;
      pools = [
        "rpool"
        "tank"
      ];
    };

    autoSnapshot = {
      enable = true;
      frequent = 2;
      hourly = 6;
      daily = 3;
      weekly = 2;
      monthly = 3;
    };

    trim.enable = true;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };

  system.stateVersion = "25.05";
}
