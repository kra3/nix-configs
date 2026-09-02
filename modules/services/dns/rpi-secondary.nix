{
  # Standalone secondary DNS resolver for hosts/surasa -- plain port-53
  # AdGuard Home + Unbound, no TLS/nginx/ACME and no sutala container-name
  # rewrites (those are sutala-only concerns, see services-dns-adguard).
  # Filter-list subscriptions are shared with sutala's instance via
  # flakeLib.adguard-filters (modules/lib/adguard-filters.nix) so both
  # block the same things.
  flake.nixosModules.services-dns-rpi-secondary =
  { config, lib, flakeLib, ... }:
  let
    net = config.vars.network;
  in
  {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "127.0.0.1" ];
          access-control = [ "127.0.0.0/8 allow" ];
          port = 5335;
          do-daemonize = false;
          prefetch = "yes";
          edns-buffer-size = 1232;
          harden-glue = "yes";
          harden-dnssec-stripped = "yes";
          use-caps-for-id = "yes";
          hide-identity = "yes";
          hide-version = "yes";
          minimal-responses = "yes";
          deny-any = "yes";
          harden-referral-path = "yes";
          harden-algo-downgrade = "yes";
          do-not-query-localhost = "yes";
        };
        remote-control.control-enable = true;
        forward-zone = [
          {
            name = ".";
            forward-tls-upstream = true;
            forward-addr = [
              "1.1.1.1@853#family.cloudflare-dns.com"
              "9.9.9.11@853#dns11.quad9.net"
            ];
          }
        ];
      };
    };

    users.groups.adguardhome = { };
    users.users.adguardhome = {
      isSystemUser = true;
      group = "adguardhome";
      home = "/var/lib/AdGuardHome";
      createHome = false;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/AdGuardHome 0750 adguardhome adguardhome - -"
    ];

    systemd.services.adguardhome.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "adguardhome";
      Group = "adguardhome";
    };

    services.adguardhome = {
      enable = true;
      # Unlike sutala's instance, no sops secret seeds the admin login here --
      # this is a LAN-only internal resolver with no TLS/nginx/ACME exposure,
      # so it's not worth making this host a sops-nix age recipient just for
      # one login. mutableSettings = true means AdGuard owns its config file
      # after first boot; set the admin user/password once via the web UI at
      # http://<pi-ip>:3000.
      mutableSettings = true;
      allowDHCP = false;
      host = net.lanIp;
      port = 3000;
      openFirewall = false;

      settings = {
        dns = {
          bind_hosts = [
            "127.0.0.1"
            net.lanIp
          ];
          port = 53;
          upstream_dns = [ "127.0.0.1:5335" ];
          upstream_mode = "load_balance";
          bootstrap_dns = [
            "9.9.9.10"
            "149.112.112.10"
          ];
          cache_size = 4194304;
          enable_dnssec = true;
        };

        filtering = {
          filtering_enabled = true;
          protection_enabled = true;
        };

        filters = flakeLib.adguard-filters;
      };
    };

    networking.firewall.interfaces.${net.lanIf} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
