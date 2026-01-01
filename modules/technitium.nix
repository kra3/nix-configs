{ lib, ... }:
{
  users.groups.technitium = {};
  users.users.technitium = {
    isSystemUser = true;
    group = "technitium";
    home = "/var/lib/technitium-dns-server";
    createHome = false;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/technitium-dns-server 0750 technitium technitium - -"
    "Z /var/lib/technitium-dns-server - technitium technitium - -"
  ];

  systemd.services.technitium-dns-server.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "technitium";
    Group = "technitium";
  };

  services.technitium-dns-server = {
    enable = true;
    openFirewall = false;
  };

  networking.firewall.interfaces.enp2s0.allowedTCPPorts = [
    53
    5380
  ];
  networking.firewall.interfaces.enp2s0.allowedUDPPorts = [ 53 ];
}
