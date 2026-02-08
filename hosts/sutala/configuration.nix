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
    inputs.nur.modules.nixos.default

    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/services/system/nix.nix
    ../../modules/vars.nix
    ../../modules/acme.nix
    ../../modules/nginx.nix
    ../../modules/openssh.nix
    ../../modules/sops.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/dns
    ../../modules/services/surveillance/proxy.nix
    ../../modules/services/mount-guards.nix
    ../../modules/services/discovery/avahi.nix
    ../../modules/services/discovery/ssdp.nix
    ../../modules/services/monitoring/agent
    ../../modules/services/media/management/agent
    ../../modules/services/media/players/agent
    ../../modules/containers/monitoring.nix
    ../../modules/containers/media-mgmt.nix
    ../../modules/containers/media-play.nix
    ../../modules/containers/home-auto.nix
    ../../modules/fail2ban.nix
    ../../modules/services/system/vim.nix
    ../../modules/services/system/sysadmin.nix
    ../../modules/users/root.nix
    ../../modules/users/kra3.nix
  ];

  vars.network = {
    lanIf = "enp2s0";
    lanIp = "192.168.1.10";
    nginxAllowCidrs = [
      "192.168.1.0/24"
      "100.64.0.0/10"
      "127.0.0.1"
      "10.0.50.2/32"
    ];
  };

  vars.acme.email = "the1.arun@gmail.com";

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI driver for Gen9+ Intel iGPU (Comet Lake)
      # intel-vaapi-driver # legacy i965 VAAPI driver fallback
      
      libva-vdpau-driver # VAAPI to VDPAU translation layer
      libvdpau-va-gl # VDPAU on top of VAAPI/OpenGL

      intel-compute-runtime-legacy1 # OpenCL/oneAPI runtime for Intel iGPU
      level-zero # Level Zero loader for OpenVINO GPU
      
      intel-media-sdk # oneVPL runtime for Intel QSV pipelines
    ];
  };

  hardware.enableRedistributableFirmware = true;

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

    # Kernel hardening parameters
    # NOTE: kernel.unprivileged_userns_clone NOT set to preserve container compatibility
    # Setting it to 0 would break Podman and potentially systemd-nspawn containers
    kernel.sysctl = {
      # Kernel hardening
      "kernel.kptr_restrict" = 2;              # Hide kernel pointers in /proc
      "kernel.dmesg_restrict" = 1;             # Restrict dmesg to root only
      "kernel.yama.ptrace_scope" = 2;          # Restrict ptrace to admin only

      # Network hardening
      "net.ipv4.tcp_syncookies" = 1;                    # SYN flood protection
      "net.ipv4.conf.all.rp_filter" = 1;                # Reverse path filtering (anti-spoofing)
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;       # Ignore broadcast pings
      "net.ipv4.conf.all.accept_redirects" = 0;         # Disable ICMP redirects
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;         # Disable secure ICMP redirects
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;           # Don't send ICMP redirects
      "net.ipv4.conf.default.send_redirects" = 0;
    };
  };

  networking = {
    hostName = "sutala";
    hostId = "d2a81622";
    enableIPv6 = false;
    firewall = {
      enable = true;
      logRefusedConnections = true;
      logRefusedPackets = true;
      logRefusedUnicastsOnly = true;
    };
    nftables.enable = true;
    nameservers = [ config.vars.network.lanIp ];
    nat = {
      enable = true;
      externalInterface = config.vars.network.lanIf;
      internalInterfaces = [
        "ve-monitoring"
        "ve-media-mgmt"
        "ve-media-play"
        "ve-home-auto"
      ];
      forwardPorts = [
        {
          sourcePort = 1883;
          destination = "10.0.50.8:1883";
          proto = "tcp";
        }
        {
          sourcePort = 8555;
          destination = "10.0.50.8:8555";
          proto = "tcp";
        }
        {
          sourcePort = 8555;
          destination = "10.0.50.8:8555";
          proto = "udp";
        }
      ];
    };
    defaultGateway = "192.168.1.1";
    interfaces.${config.vars.network.lanIf}.ipv4.addresses = [
      {
        address = config.vars.network.lanIp;
        prefixLength = 24;
      }
    ];
  };


  time.timeZone = "UTC";

  services.journald.extraConfig = ''
    SystemMaxUse=200M
    SystemMaxFileSize=50M
    MaxRetentionSec=12h
  '';

  services.logrotate.enable = true;
  systemd.timers.logrotate.timerConfig.OnCalendar = "*-*-* 00,12:00:00";

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
