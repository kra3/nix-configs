{
  inputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager

    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nix.nix
    ../../modules/vars.nix
    ../../modules/acme.nix
    ../../modules/nginx.nix
    ../../modules/openssh.nix
    ../../modules/sops.nix
    ../../modules/services/dns
    ../../modules/services/discovery/mdns.nix
    ../../modules/services/monitoring/agent
    ../../modules/services/media/management/agent
    ../../modules/services/media/players/agent
    ../../modules/containers/monitoring.nix
    ../../modules/containers/media-mgmt.nix
    ../../modules/containers/media-play.nix
    ../../modules/fail2ban.nix
    ../../modules/vim.nix
    ../../modules/users/root.nix
    ../../modules/users/kra3.nix
  ];

  vars = {
    lanIf = "enp2s0";
    lanIp = "192.168.1.10";
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI driver for Gen9+ Intel iGPU (Comet Lake)
      intel-vaapi-driver # legacy i965 VAAPI driver fallback
      libva-vdpau-driver # VAAPI to VDPAU translation layer
      libvdpau-va-gl # VDPAU on top of VAAPI/OpenGL
      intel-compute-runtime # OpenCL/oneAPI runtime for Intel iGPU
      vpl-gpu-rt # oneVPL runtime for Intel QSV pipelines
    ];
  };

  boot = {
    loader = {
      systemd-boot = { 
        enable = true;
        configurationLimit = 5;
      };
      efi.canTouchEfiVariables = true;
    };

    kernelModules = [ "i915" ];
    supportedFilesystems = [ "zfs" ];
    kernelParams = [
      "zfs.zfs_arc_max=3338665984" # zfs
      "ipv6.disable=1"  # networking 
      "i915.enable_guc=2" # QSV low-power encode/decode requires HuC/GuC firmware
      "i915.enable_fbc=1" # allow framebuffer compression to reduce power draw
    ];
    zfs.extraPools = [ "tank" ];
  };

  networking = {
    hostName = "sutala";
    hostId = "d2a81622";
    enableIPv6 = false;
    firewall.enable = true;
    nftables.enable = true;
    nameservers = [ config.vars.lanIp ];
    nat = {
      enable = true;
      externalInterface = config.vars.lanIf;
      internalInterfaces = [
        "ve-monitoring"
        "ve-media-mgmt"
        "ve-media-play"
      ];
    };
    defaultGateway = "192.168.1.1";
    interfaces.${config.vars.lanIf}.ipv4.addresses = [
      {
        address = config.vars.lanIp;
        prefixLength = 24;
      }
    ];
  };


  time.timeZone = "UTC";

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
