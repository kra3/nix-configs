{ config, lib, pkgs, ... }:
let
  cfg = config.vars;
  lanIf = cfg.lanIf;
  lanIp = cfg.lanIp;
  adguardFilters = [
    {
      enabled = false;
      url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
      name = "StevenBlack";
      id = 1;
    }
    {
      enabled = false;
      url = "https://big.oisd.nl/";
      name = "OISD";
      id = 2;
    }
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
  options.vars = {
    lanIf = lib.mkOption {
      type = lib.types.str;
      default = "enp2s0";
    };
    lanIp = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.10";
    };
  };

  config = {
    users.groups.adguardhome = { };
    users.users.adguardhome = {
      isSystemUser = true;
      group = "adguardhome";
      home = "/var/lib/AdGuardHome";
      createHome = false;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/AdGuardHome 0750 adguardhome adguardhome - -"
      "Z /var/lib/AdGuardHome - adguardhome adguardhome - -"
    ];

    systemd.services.adguardhome.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "adguardhome";
      Group = "adguardhome";
    };

    sops.secrets."dns.adguard.password" = {
      owner = "adguardhome";
      group = "adguardhome";
      mode = "0440";
    };
    sops.secrets."dns.adguard.username" = {
      owner = "adguardhome";
      group = "adguardhome";
      mode = "0440";
    };

    systemd.services.adguardhome.preStart = lib.mkAfter ''
      if [ -f "$STATE_DIRECTORY/AdGuardHome.yaml" ]; then
        password="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets."dns.adguard.password".path})"
        ${pkgs.gnused}/bin/sed -i "s|__SOPS_DNS_ADGUARD_PASSWORD__|$password|" \
          "$STATE_DIRECTORY/AdGuardHome.yaml"
        username="$(${pkgs.coreutils}/bin/tr -d '\n' < ${config.sops.secrets."dns.adguard.username".path})"
        ${pkgs.gnused}/bin/sed -i "s|__SOPS_DNS_ADGUARD_USERNAME__|$username|" \
          "$STATE_DIRECTORY/AdGuardHome.yaml"
      fi
    '';

    services.adguardhome = {
      enable = true;
      mutableSettings = false;
      allowDHCP = false;

      host = "127.0.0.1";
      port = 3000;
      openFirewall = false;

      settings = {
        schema_version = config.services.adguardhome.package.schema_version;
        http.session_ttl = "10m";
        theme = "auto";
        auth_attempts = 3;
        block_auth_min = 15;

        dns = {
          bind_hosts = [
            "127.0.0.1"
            lanIp
          ];
          port = 53;
          anonymize_client_ip = true;
          upstream_dns = [ "127.0.0.1:5335" ];
          upstream_dns_file = "";
          bootstrap_dns = [
            "9.9.9.10"
            "149.112.112.10"
            "2620:fe::10"
            "2620:fe::fe:10"
          ];
          fallback_dns = [ ];
          upstream_mode = "load_balance";
          fastest_timeout = "1s";
          trusted_proxies = [
            "127.0.0.0/8"
            "::1/128"
          ];
          cache_size = 4194304;
          cache_ttl_min = 0;
          cache_ttl_max = 0;
          bogus_nxdomain = [ ];
          aaaa_disabled = false;
          enable_dnssec = true;
          edns_client_subnet = {
            enabled = false;
            use_custom = false;
          };
          handle_ddr = true;
          bootstrap_prefer_ipv6 = false;
          upstream_timeout = "10s";
          use_private_ptr_resolvers = true;
          local_ptr_upstreams = [ "127.0.0.1:5335" ];
          use_dns64 = false;
          serve_http3 = false;
          use_http3_upstreams = false;
          serve_plain_dns = true;
          hostsfile_enabled = true;
          pending_requests.enabled = true;
        };

        tls = {
          enabled = false;
          allow_unencrypted_doh = true;
          server_name = "";
          force_https = false;
          port_https = 443;
          port_dns_over_tls = 853;
          port_dns_over_quic = 853;
          port_dnscrypt = 0;
          dnscrypt_config_file = "";
          certificate_chain = "";
          private_key = "";
          certificate_path = "";
          private_key_path = "";
          strict_sni_check = false;
        };

        filtering = {
          safe_search = {
            enabled = true;
            bing = true;
            duckduckgo = true;
            ecosia = true;
            google = true;
            pixabay = true;
            yandex = true;
            youtube = false;
          };
          blocking_mode = "default";
          rewrites = [
            {
              domain = "*.karunagath.in";
              answer = lanIp;
              enabled = true;
            }
          ];
          cache_time = 30;
          filters_update_interval = 1;
          blocked_response_ttl = 10;
          filtering_enabled = true;
          parental_enabled = false;
          safebrowsing_enabled = false;
          protection_enabled = true;
        };

        filters = adguardFilters;
        whitelist_filters = [ ];

        user_rules = [
          "||adservice.google.*^$important"
          "||adsterra.com^$important"
          "||amplitude.com^$important"
          "||analytics.edgekey.net^$important"
          "||analytics.twitter.com^$important"
          "||app.adjust.*^$important"
          "||app.*.adjust.com^$important"
          "||app.appsflyer.com^$important"
          "||doubleclick.net^$important"
          "||googleadservices.com^$important"
          "||guce.advertising.com^$important"
          "||metric.gstatic.com^$important"
          "||mmstat.com^$important"
          "||statcounter.com^$important"
        ];
 
        querylog = {
          interval = "1h";
          size_memory = 1000;
          enabled = true;
          file_enabled = true;
        };

        statistics = {
          interval = "1h";
          enabled = true;
        };

        clients = {
          runtime_sources = {
            whois = true;
            arp = true;
            rdns = true;
            dhcp = true;
            hosts = true;
          };
          persistent = [ ];
        };

        log = {
          enabled = true;
          max_backups = 0;
          max_size = 100;
          max_age = 3;
          local_time = true;
        };
        users = [
          {
            name = "__SOPS_DNS_ADGUARD_USERNAME__";
            password = "__SOPS_DNS_ADGUARD_PASSWORD__";
          }
        ];
      };
    };

    services.nginx.virtualHosts."dns.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = ''
        allow 192.168.1.0/24;
        allow 127.0.0.1;
        deny all;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
      locations."/dns-query" = {
        proxyPass = "http://127.0.0.1:3000";
      };
    };

    networking.firewall.interfaces.${lanIf} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
