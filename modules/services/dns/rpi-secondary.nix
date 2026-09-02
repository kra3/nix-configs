{
  # Standalone secondary DNS resolver for hosts/surasa -- plain port-53
  # AdGuard Home + Unbound, no TLS/nginx/ACME and no sutala container-name
  # rewrites (those are sutala-only concerns, see services-dns-adguard).
  # Same filter-list subscriptions as sutala's instance so both block the
  # same things; kept as a separate literal rather than a shared import,
  # since two DNS filter-list copies isn't worth a shared abstraction yet.
  flake.nixosModules.services-dns-rpi-secondary =
  { config, lib, ... }:
  let
    net = config.vars.network;
    adguardFilters = [
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_53.txt";
        name = "AWAvenue Ads Rule";
        id = 1767444735;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_59.txt";
        name = "AdGuard DNS Popup Hosts filter";
        id = 1767444736;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        name = "AdGuard DNS filter";
        id = 1767444737;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt";
        name = "Dan Pollock's List";
        id = 1767444738;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_51.txt";
        name = "HaGeZi's Pro++ Blocklist";
        id = 1767444739;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt";
        name = "Peter Lowe's Blocklist";
        id = 1767444740;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_33.txt";
        name = "Steven Black's List";
        id = 1767444741;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_27.txt";
        name = "OISD Blocklist Big";
        id = 1767444742;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_39.txt";
        name = "Dandelion Sprout's Anti Push Notifications";
        id = 1767444743;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_6.txt";
        name = "Dandelion Sprout's Game Console Adblock List";
        id = 1767444744;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_45.txt";
        name = "HaGeZi's Allowlist Referral";
        id = 1767444745;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_47.txt";
        name = "HaGeZi's Gambling Blocklist";
        id = 1767444746;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_61.txt";
        name = "HaGeZi's Samsung Tracker Blocklist";
        id = 1767444747;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_63.txt";
        name = "HaGeZi's Windows/Office Tracker Blocklist";
        id = 1767444748;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt";
        name = "Perflyst and Dandelion Sprout's Smart-TV Blocklist";
        id = 1767444749;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_17.txt";
        name = "SWE: Frellwit's Swedish Hosts File";
        id = 1767444750;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_30.txt";
        name = "Phishing URL Blocklist (PhishTank and OpenPhish)";
        id = 1767444751;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt";
        name = "Dandelion Sprout's Anti-Malware List";
        id = 1767444752;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_55.txt";
        name = "HaGeZi's Badware Hoster Blocklist";
        id = 1767444753;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_56.txt";
        name = "HaGeZi's The World's Most Abused TLDs";
        id = 1767444754;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_54.txt";
        name = "HaGeZi's DynDNS Blocklist";
        id = 1767444755;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_44.txt";
        name = "HaGeZi's Threat Intelligence Feeds";
        id = 1767444756;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt";
        name = "NoCoin Filter List";
        id = 1767444757;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt";
        name = "Phishing Army";
        id = 1767444758;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_10.txt";
        name = "Scam Blocklist by DurableNapkin";
        id = 1767444759;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_42.txt";
        name = "ShadowWhisperer's Malware List";
        id = 1767444760;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_31.txt";
        name = "Stalkerware Indicators List";
        id = 1767444761;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt";
        name = "The Big List of Hacked Malware Web Sites";
        id = 1767444762;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_50.txt";
        name = "uBlock0 filters - Badware risks";
        id = 1767444763;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt";
        name = "Malicious URL Blocklist (URLHaus)";
        id = 1767444764;
      }
      {
        enabled = true;
        url = "https://v.firebog.net/hosts/Admiral.txt";
        name = "Admiral";
        id = 1767444765;
      }
    ];
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

        filters = adguardFilters;
      };
    };

    networking.firewall.interfaces.${net.lanIf} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
