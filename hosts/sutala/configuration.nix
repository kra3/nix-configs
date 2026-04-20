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
    ../../modules/services/system/nix.nix
    ../../modules/vars.nix
    ../../modules/services/infrastructure/acme.nix
    ../../modules/services/proxy/nginx.nix
    ../../modules/services/infrastructure/openssh.nix
    ../../modules/services/infrastructure/sops.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/dns
    ../../modules/services/postgres.nix
    ../../modules/services/redis.nix
    ../../modules/services/surveillance/proxy.nix
    ../../modules/services/discovery/avahi.nix
    ../../modules/containers/monitoring.nix
    ../../modules/containers/media-mgmt
    ../../modules/containers/media-play.nix
    ../../modules/containers/home-auto.nix
    ../../modules/containers/home-auto/home-assistant
    ../../modules/containers/home-auto/otbr
    ../../modules/containers/home-auto/matter-server
    ../../modules/containers/life
    ../../modules/fail2ban.nix
    ../../modules/services/system/vim.nix
    ../../modules/services/system/sysadmin.nix
    ../../modules/services/virtualisation
    ../../modules/users/root.nix
    ../../modules/users/kra3.nix
  ];

  vars.network = {
    lanIf = "enp2s0";
    lanIp = "192.168.1.10";
    nginxAllowCidrs = [
      config.vars.network.lanCidr
      "100.64.0.0/10"
      "127.0.0.1"
      config.vars.network.containers.monitoring.localAddress
      config.vars.network.podmanSubnets.homeAuto
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
      filterForward = true;
      logRefusedConnections = true;
      logRefusedPackets = true;
      logRefusedUnicastsOnly = true;
      # Default-deny inter-zone FORWARD policy with explicit allows
      extraForwardRules = let
        c     = config.vars.network.containers;
        p     = config.vars.network.podmanSubnets;
        mon   = c.monitoring.localAddress;
        mp    = c.mediaPlay.localAddress;
        ha    = c.homeAuto.localAddress;
        haNet = p.homeAuto;
        mmNet = p.mediaMgmt;
        liNet = p.life;
        lan   = config.vars.network.lanCidr;
      in ''
        # 1. monitoring → media-play: scrape node-exporter + navidrome metrics
        ip saddr ${mon} ip daddr ${mp} tcp dport { 9100, 4533 } accept
        # 2. monitoring → home-auto: scrape node-exporter + frigate metrics
        ip saddr ${mon} ip daddr ${ha} tcp dport { 9100, 80 } accept
        # 3. monitoring → HA pod: scrape Home Assistant Prometheus endpoint
        ip saddr ${mon} ip daddr ${haNet} tcp dport 8123 accept
        # 4. home-auto → monitoring: ship logs via Alloy → Loki
        ip saddr ${ha} ip daddr ${mon} tcp dport 3100 accept
        # 5. media-play → monitoring: ship logs via Alloy → Loki
        ip saddr ${mp} ip daddr ${mon} tcp dport 3100 accept
        # 6. HA pod → home-auto: HA talks to MQTT + Frigate
        ip saddr ${haNet} ip daddr ${ha} tcp dport { 1883, 5000 } accept
        # 7. home-auto → HA pod: Frigate notifications / automations
        ip saddr ${ha} ip daddr ${haNet} tcp dport 8123 accept
        # 8. HA pod → media-play: HA media_player integration (Jellyfin)
        ip saddr ${haNet} ip daddr ${mp} tcp dport 8096 accept
        # 9. media-mgmt pods → media-play: Seerr authenticates against Jellyfin
        ip saddr ${mmNet} ip daddr ${mp} tcp dport 8096 accept
        # 10. HA pod → media-play: HA media_player integration (Music Assistant)
        ip saddr ${haNet} ip daddr ${mp} tcp dport 8095 accept
        # 11. LAN → home-auto: DNAT for MQTT + WebRTC
        ip saddr ${lan} ip daddr ${ha} tcp dport { 1883, 8555 } accept
        ip saddr ${lan} ip daddr ${ha} udp dport 8555 accept
        # 12. Podman subnets → internet (outbound NAT)
        ip saddr ${liNet} accept comment "life pods outbound"
        ip saddr ${mmNet} accept comment "media-mgmt pods outbound"
        ip saddr ${haNet} accept comment "home-auto pods outbound"
      '';
    };
    nftables.enable = true;
    nameservers = [ config.vars.network.lanIp ];
    nat = {
      enable = true;
      externalInterface = config.vars.network.lanIf;
      internalInterfaces = [
        "ve-monitoring"
        "ve-media-play"
        "ve-home-auto"
      ];
      forwardPorts = [
        {
          sourcePort = 1883;
          destination = "${config.vars.network.containers.homeAuto.localAddress}:1883";
          proto = "tcp";
        }
        {
          sourcePort = 8555;
          destination = "${config.vars.network.containers.homeAuto.localAddress}:8555";
          proto = "tcp";
        }
        {
          sourcePort = 8555;
          destination = "${config.vars.network.containers.homeAuto.localAddress}:8555";
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
    sharedModules = [ inputs.catppuccin.homeModules.catppuccin ];
  };

  system.stateVersion = "25.05";
}
