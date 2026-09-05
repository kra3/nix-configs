{
  config,
  lib,
  flakeModules,
  ...
}:
{
  imports = [
    # Board profile, sd-image module, cache trust, and overlays are all imported in flake/hosts.nix.
    flakeModules.nixos.vars
    flakeModules.nixos.services-infrastructure-openssh
    flakeModules.nixos.services-infrastructure-sops
    flakeModules.nixos.services-dns-rpi-secondary
    flakeModules.nixos.services-media-snapclient
    flakeModules.nixos.services-monitoring-sutala-watchdog
    flakeModules.nixos.services-monitoring-alloy-host
    flakeModules.nixos.services-system-nix-defaults-nixos
  ];

  networking.hostName = "surasa";

  # The minimal profiles/base.nix this board's sd-image imports doesn't add systemd's own
  # package to services.dbus.packages (a standard-profile default), so systemd's D-Bus policy
  # (granting root/wheel access to org.freedesktop.systemd1) never gets included -- breaking
  # switch-to-configuration's live activation ("Sender is not authorized to send message"
  # when subscribing to job-completion signals) and even `systemctl reboot`.
  services.dbus.packages = [ config.systemd.package ];

  # The sd-image module's own disabledModules entry for profiles/all-hardware.nix has a path
  # bug (missing a "/"), so it doesn't actually take effect -- that profile's broad
  # supportedFilesystems (btrfs/cifs/f2fs/ntfs/xfs/zfs) leaks in and, since zfs's kernel
  # module comes from a different nixpkgs pin than its userspace tools here, trips a version
  # mismatch assertion. Surasa needs none of this; override to what the SD card actually uses.
  boot.supportedFilesystems = lib.mkForce [
    "vfat"
    "ext4"
  ];

  # The stock expand-root-partition service hangs on real MMC hardware (partprobe can't
  # notify the kernel of the new boundaries while root is mounted from the same disk),
  # and since it gates sysinit.target, that hang blocks boot entirely -- nothing after it
  # (network, sshd) ever starts. Not essential; grow manually via SSH later if needed.
  sdImage.expandOnBoot = false;

  # nix-store --load-db for the whole closure saturates this hardware's SD I/O badly enough
  # that it stalls the entire system, not just units ordered after it -- deprioritizing it
  # (removing it from sysinit.target's Before=) wasn't enough, so disable it outright. Its
  # job (registering paths, pointing the system profile at the booted generation) gets
  # redone correctly by the first real switch-remote deploy anyway.
  systemd.services.register-nix-paths.enable = lib.mkForce false;

  vars.network = {
    lanIf = "wlan0";
    lanIp = "192.168.1.39";
  };

  networking = {
    enableIPv6 = false;
    firewall.enable = true;
    nftables.enable = true;
    nameservers = [ "127.0.0.1" ];
    networkmanager.enable = true;
  };

  # The bootstrap ethernet adapter staying plugged in on the same LAN as wlan0 causes ARP flux, silently missing `iifname "wlan0"` firewall rules.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };

  # Unlike Raspberry Pi OS's raspi-config, NixOS never sets a regdomain, leaving 5GHz DFS channels rejected until an AP's beacon happens to override it.
  boot.kernelParams = [ "cfg80211.ieee80211_regdom=SE" ];

  # Loki's container address isn't routable off sutala's host -- push via the loki.<domain> vhost instead.
  services.monitoringAlloyHost.lokiUrl = "https://loki.${config.vars.acme.domain}/loki/api/v1/push";

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    openFirewall = false;
  };
  networking.firewall.interfaces.wlan0.allowedTCPPorts = [ 9100 ];

  # Logs already ship to Loki via Alloy above -- skip persisting them locally too, to cut SD card writes.
  services.journald.storage = "volatile";
  services.journald.extraConfig = "RuntimeMaxUse=32M";

  # services-infrastructure-openssh only opens port 22 on vars.network.lanIf (wlan0) -- fine
  # for sutala's single interface, but surasa's first boot (and sops bootstrap) happens over
  # ethernet, before wifi is even configured. Predictable interface naming means the USB
  # ethernet chip isn't actually "eth0", so open globally rather than guess its real name --
  # no real security loss since SSH is already key-only auth-gated.
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Can't decrypt until surasa is a sops recipient (same first-boot chicken-and-egg as the tailscale key below),
  # so this only takes effect once the post-first-boot bootstrap is done -- first boot itself joins via ethernet.
  sops.secrets."surasa.wifi.ssid" = { };
  sops.secrets."surasa.wifi.psk" = { };
  sops.templates."surasa-wifi.env".content = ''
    WIFI_SSID=${config.sops.placeholder."surasa.wifi.ssid"}
    WIFI_PSK=${config.sops.placeholder."surasa.wifi.psk"}
  '';
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."surasa-wifi.env".path ];
    profiles."surasa-wifi" = {
      connection = {
        id = "surasa-wifi";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "$WIFI_SSID";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$WIFI_PSK";
      };
      # wlan0 and the bootstrap ethernet adapter share the same /24; enu1u1u1's lower metric always won the on-link route, so wlan0-received traffic replied out the wrong interface and got dropped upstream as spoofed.
      ipv4.method = "auto";
      ipv4.route-table = 100;
      ipv4.routing-rule1 = "priority 100 from ${config.vars.network.lanIp} table 100";
      ipv6.method = "disabled";
    };
  };

  # Firmware/bootloader (config.txt, /boot/firmware sync) and kernel package are all handled
  # by the raspberry-pi-3.base module (flake/hosts.nix) via mkDefault, cached on cachix.

  # TODO(surasa): needs its own sops age recipient before this (and surasa-wifi.env above) decrypt for real -- after first boot: ssh-to-age its host key, add `&surasa` to .sops.yaml, `sops updatekeys`, then `sops set` a real Tailscale auth key (a fresh key per device; wifi SSID/psk are already set).
  sops.secrets."surasa.tailscale.authkey" = { };

  # Plain tailnet member (not an exit node like sutala's) so surasa/SSH stays reachable even when sutala is down.
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."surasa.tailscale.authkey".path;
    openFirewall = true;
  };

  # kra3 has no password set on surasa, so sudo (needed by switch-remote) can never succeed by
  # default. SSH is already key-only (services-infrastructure-openssh sets
  # PasswordAuthentication = false), so a sudo password isn't adding real security here --
  # possessing an authorized key already grants full account control.
  security.sudo.wheelNeedsPassword = false;

  users.mutableUsers = true;
  users.users.kra3 = {
    isNormalUser = true;
    # /dev/snd/* is group-owned "audio"; without it, WirePlumber can't open the onboard headphone/HDMI cards.
    extraGroups = [ "wheel" "audio" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpvhVfQVKDNfVyl4GJux/lfzjkm683EW4MAESX/JKQA sutala kra3"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFHJcFS3rx+AoqmqhHSjMbWpe8KqcLTmX/xgcf7/lTn nixos-deploy"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKmRf86XKYHd45ZmhhjyXFSgl88nH91dcSvRVNhVwn91 kra3@sutala github"
    ];
  };

  time.timeZone = "UTC";

  # This board has no RTC, so it boots with a stale clock -- and our DNS resolver forwards
  # exclusively over DoT (see services-dns-rpi-secondary), which fails TLS validation until the
  # clock is right. NTP's default servers are hostnames, which need DNS to resolve, deadlocking
  # cold boot entirely. Bootstrap the clock via IP so NTP never depends on our own DNS resolver.
  networking.timeServers = [
    "216.239.35.0"
    "216.239.35.4"
    "216.239.35.8"
    "216.239.35.12"
  ];

  nix.settings = {
    # Lets switch-remote's build-on-sutala-copy-to-surasa path work without the ephemeral
    # /run systemd drop-in this session used to bootstrap it. root is trusted by default
    # (NixOS's own nix module already includes it), so only kra3 needs adding here.
    trusted-users = [ "kra3" ];
  };

  # services-system-nix-defaults-nixos's weekly/7d gc and 5-generation systemd-boot limit are
  # tuned for sutala's disk; this SD card is both far smaller and wears out on write volume, so
  # collect more often and keep fewer generations around as gcroots.
  nix.gc = {
    dates = lib.mkForce "daily";
    options = lib.mkForce "--delete-older-than 3d";
  };
  boot.loader.generic-extlinux-compatible.configurationLimit = 3;

  system.stateVersion = "26.05";
}
