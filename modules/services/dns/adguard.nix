{
  flake.nixosModules.services-dns-adguard =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      cfg = config.vars.network;
      domain = config.vars.acme.domain;
      lanIf = cfg.lanIf;
      lanIp = cfg.lanIp;
      allowBlock = flakeLib.nginx.mkAllowBlock cfg.nginxAllowCidrs;
    in
    {
      config = {
        users.groups.adguardhome = { };
        users.users.adguardhome = {
          isSystemUser = true;
          group = "adguardhome";
          extraGroups = [ "acme" ];
          home = "/var/lib/AdGuardHome";
          createHome = false;
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/AdGuardHome 0750 adguardhome adguardhome - -"
          "Z /var/lib/AdGuardHome - adguardhome adguardhome - -"
          # AdGuardHome creates data/ (and the query log/stats files in it)
          # itself at 0700, which blocks the alloy user's "adguardhome" group
          # membership from reading the query log for log shipping; recursively
          # re-widen it to group-readable on every activation.
          "Z /var/lib/AdGuardHome/data 0750 adguardhome adguardhome - -"
        ];

        systemd.services.adguardhome.serviceConfig = lib.mkMerge [
          {
            DynamicUser = lib.mkForce false;
            User = "adguardhome";
            Group = "adguardhome";
            SupplementaryGroups = [ "acme" ];
            LoadCredential = [
              "password:${config.sops.secrets."dns.adguard.password".path}"
              "username:${config.sops.secrets."dns.adguard.username".path}"
            ];
          }
          (flakeLib.deployment-hardening.mkServiceSandbox {
            readWritePaths = [ "/var/lib/AdGuardHome" ];
            capabilities = [ "CAP_NET_BIND_SERVICE" ];
          })
        ];

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

        systemd.services.adguardhome.preStart =
          let
            setupScript = pkgs.writeShellScript "adguard-setup" ''
              set -euo pipefail

              if [ -f "$STATE_DIRECTORY/AdGuardHome.yaml" ]; then
                # Read credentials from systemd credential directory (secure, not visible in ps)
                PASSWORD=$(${pkgs.coreutils}/bin/cat "''${CREDENTIALS_DIRECTORY}/password" | ${pkgs.coreutils}/bin/tr -d '\n')
                USERNAME=$(${pkgs.coreutils}/bin/cat "''${CREDENTIALS_DIRECTORY}/username" | ${pkgs.coreutils}/bin/tr -d '\n')

                # Create temporary sed script to avoid password in command line
                SCRIPT=$(${pkgs.coreutils}/bin/mktemp)
                trap "${pkgs.coreutils}/bin/rm -f $SCRIPT" EXIT

                # Write sed commands to temp file (not visible in ps)
                cat > "$SCRIPT" <<EOF
              s|__SOPS_DNS_ADGUARD_PASSWORD__|$PASSWORD|
              s|__SOPS_DNS_ADGUARD_USERNAME__|$USERNAME|
              EOF

                # Execute sed with script file (no secrets in command line)
                ${pkgs.gnused}/bin/sed -i -f "$SCRIPT" "$STATE_DIRECTORY/AdGuardHome.yaml"
              fi
            '';
          in
          lib.mkAfter (toString setupScript);

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
                "100.119.26.45"
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
              enabled = true;
              allow_unencrypted_doh = false;
              server_name = "dns.${domain}";
              force_https = false;
              port_https = 3001;
              port_dns_over_tls = 853;
              port_dns_over_quic = 853;
              port_dnscrypt = 0;
              dnscrypt_config_file = "";
              certificate_path = "${config.security.acme.certs.${domain}.directory}/fullchain.pem";
              private_key_path = "${config.security.acme.certs.${domain}.directory}/key.pem";
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
                  domain = "*.${domain}";
                  answer = lanIp;
                  enabled = true;
                }
                # Container name resolution
                {
                  domain = "monitoring";
                  answer = cfg.containers.monitoring.localAddress;
                  enabled = true;
                }
                {
                  domain = "media-play";
                  answer = cfg.containers.mediaPlay.localAddress;
                  enabled = true;
                }
                {
                  domain = "home-auto";
                  answer = cfg.containers.homeAuto.localAddress;
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

            filters = flakeLib.adguard-filters;
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
              # thexem.info: legit Sonarr/Radarr scene-numbering API; needs $important to beat a blocklist rule that also has it.
              "@@||thexem.info^$important"
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

            dhcp = {
              enabled = false;
            };

            clients = {
              runtime_sources = {
                whois = true;
                arp = true;
                rdns = true;
                dhcp = false;
                hosts = true;
              };
              persistent = [ ];
            };

            log = {
              enabled = true;
              max_backups = 1;
              max_size = 100;
              max_age = 1;
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

        services.nginx.virtualHosts."dns.${domain}" = {
          useACMEHost = domain;
          forceSSL = true;
          extraConfig = allowBlock;
          locations."/" = {
            proxyPass = "https://127.0.0.1:3001";
            proxyWebsockets = true;
          };
          locations."/dns-query" = {
            proxyPass = "https://127.0.0.1:3001";
          };
        };

        networking.firewall.interfaces.${lanIf} = {
          allowedTCPPorts = [ 53 ];
          allowedUDPPorts = [ 53 ];
        };

        services.logrotate.settings.adguardhome = {
          files = [
            "/var/lib/AdGuardHome/data/*.log"
            "/var/lib/AdGuardHome/data/querylog.json"
            "/var/lib/AdGuardHome/data/stats.json"
          ];
          rotate = 1;
          frequency = "hourly";
          compress = true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          copytruncate = true;
          su = "adguardhome adguardhome";
        };
        environment.etc."alloy/adguardhome.alloy".text = ''
          loki.source.file "adguardhome" {
            targets = [
              {
                __path__ = "/var/lib/AdGuardHome/data/*.log",
                job = "adguardhome",
                host = "${config.networking.hostName}",
                role = "${if config.boot.isContainer then "container" else "host"}",
              },
              {
                __path__ = "/var/lib/AdGuardHome/data/*.json",
                job = "adguardhome",
                host = "${config.networking.hostName}",
                role = "${if config.boot.isContainer then "container" else "host"}",
              },
            ]
            forward_to = [loki.write.default.receiver]
          }
        '';
      };
    };
}
