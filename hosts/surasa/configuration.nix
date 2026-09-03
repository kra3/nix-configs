{
  config,
  modulesPath,
  flakeModules,
  ...
}:
{
  imports = [
    # Board-specific kernel/config.txt/bootloader (raspberry-pi-3 profile) is
    # imported by flake/hosts.nix, alongside this file. This module supplies
    # the SD-image-build machinery (fileSystems, populateRootCommands, image
    # assembly) -- see the Context notes in the plan for why this composes
    # safely with the board profile's own firmware install (it mkForces the
    # one option they'd otherwise both set).
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")

    flakeModules.nixos.vars
    flakeModules.nixos.services-infrastructure-openssh
    flakeModules.nixos.services-infrastructure-sops
    flakeModules.nixos.services-dns-rpi-secondary
    flakeModules.nixos.services-media-snapclient
  ];

  networking.hostName = "surasa";

  # TODO(surasa): this host is wifi-only going forward (no ethernet) and its
  # static LAN IP isn't reserved/known yet -- placeholder below. Once it is:
  # set vars.network.lanIp to the real reservation, wire up
  # networking.networkmanager.ensureProfiles (or a wpa_supplicant network
  # block) with the actual SSID/psk (as a sops secret, not plaintext), and
  # add the router-side DHCP reservation for that IP.
  vars.network = {
    lanIf = "wlan0";
    lanIp = "192.168.1.20";
  };

  networking = {
    enableIPv6 = false;
    firewall.enable = true;
    nftables.enable = true;
    nameservers = [ "127.0.0.1" ];
    # NetworkManager over declarative wpa_supplicant: no SSID/psk known yet,
    # so wifi is joined interactively (nmtui/nmcli) once the device is in
    # hand -- see the TODO above for making it declarative afterwards.
    networkmanager.enable = true;
  };

  # Repopulate the firmware partition on every switch (not just the initial
  # SD image), and chainload U-Boot from it -- see raspberry-pi-3 profile.
  hardware.raspberry-pi.firmware = {
    enable = true;
    uboot.enable = true;
  };

  # TODO(surasa): sops-nix is declared here but not yet usable -- its age
  # recipient is derived from THIS host's own ssh_host_ed25519_key, which
  # doesn't exist until first boot. After first boot:
  #   1. ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub (on surasa) to get
  #      its age public key.
  #   2. Add that as a new `&surasa` entry in .sops.yaml's keys/creation_rules.
  #   3. sops updatekeys secrets/secrets.yaml (rekeys for the new recipient;
  #      requires an existing recipient's private key to do the re-encrypt).
  #   4. sops set 'secrets/secrets.yaml' '["surasa.tailscale.authkey"]'
  #      '"<value>"' with a freshly generated Tailscale auth key (a fresh key
  #      per device, not sutala's reused). monitoring.grafana.telegram_bot_token/
  #      telegram_chat_id already exist -- once surasa is a recipient it can
  #      decrypt those same values itself, no new key needed there.
  sops.secrets."surasa.tailscale.authkey" = { };

  # Plain tailnet member, not an exit node/route-advertiser like sutala's own
  # services-tailscale -- this is here so surasa (and thus SSH) stays
  # reachable even when sutala is fully down, which is the same reasoning as
  # services-monitoring-sutala-watchdog above.
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
