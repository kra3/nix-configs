{
  config,
  lib,
  pkgs,
  modulesPath,
  flakeModules,
  ...
}:
{
  imports = [
    # Board profile (kernel/config.txt/bootloader) is imported in flake/hosts.nix; this supplies the SD-image build machinery.
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")

    flakeModules.nixos.vars
    flakeModules.nixos.services-infrastructure-openssh
    flakeModules.nixos.services-infrastructure-sops
    flakeModules.nixos.services-dns-rpi-secondary
    flakeModules.nixos.services-media-snapclient
    flakeModules.nixos.services-monitoring-sutala-watchdog
  ];

  networking.hostName = "surasa";

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
      ipv4.method = "auto";
      ipv6.method = "disabled";
    };
  };

  # Repopulate the firmware partition on every switch, not just the initial SD image.
  hardware.raspberry-pi.firmware = {
    enable = true;
    uboot.enable = true;
  };

  # Tried overriding to pkgs.linuxPackages (mainline) to avoid the vendor kernel's uncached
  # multi-hour compiles -- see https://discourse.nixos.org/t/nixos-26-05-raspberry-pi-4-kernel-cache-missing/78125.
  # Reverted: mainline's dwc2 USB controller driver got stuck in probe on this hardware
  # ("raspberrypi-power soc:power: sync_state() pending due to 3f980000.usb" in the kernel
  # log), so USB ethernet/wifi never came up and the board was never network-reachable.
  # Back to the profile's vendor linux-rpi kernel (mkDefault), slow first build and all.

  # TODO(surasa): needs its own sops age recipient before this (and surasa-wifi.env above) decrypt for real -- after first boot: ssh-to-age its host key, add `&surasa` to .sops.yaml, `sops updatekeys`, then `sops set` a real Tailscale auth key (a fresh key per device; wifi SSID/psk are already set).
  sops.secrets."surasa.tailscale.authkey" = { };

  # Plain tailnet member (not an exit node like sutala's) so surasa/SSH stays reachable even when sutala is down.
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."surasa.tailscale.authkey".path;
    openFirewall = true;
  };

  users.mutableUsers = true;
  users.users.kra3 = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpvhVfQVKDNfVyl4GJux/lfzjkm683EW4MAESX/JKQA sutala kra3"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFHJcFS3rx+AoqmqhHSjMbWpe8KqcLTmX/xgcf7/lTn nixos-deploy"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKmRf86XKYHd45ZmhhjyXFSgl88nH91dcSvRVNhVwn91 kra3@sutala github"
    ];
  };

  time.timeZone = "UTC";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}
