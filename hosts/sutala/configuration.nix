{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nix.nix
    ../../modules/openssh.nix
    ../../modules/sops.nix
    ../../users/kra3.nix
  ];

  networking.hostName = "sutala";
  networking.hostId = "d2a81622";

  time.timeZone = "UTC";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelParams = [ "zfs.zfs_arc_max=3338665984" ];
  boot.zfs.extraPools = [ "tank" ];

  services.zfs.autoScrub = {
    enable = true;
    pools = [
      "rpool"
      "tank"
    ];
  };

  services.zfs.autoSnapshot = {
    enable = true;
    frequent = 2;
    hourly = 6;
    daily = 3;
    weekly = 2;
    monthly = 3;
  };
  services.zfs.trim.enable = true;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };
  home-manager.users.kra3 = import ../../home/kra3.nix;

  system.stateVersion = "25.05";
}
