{
  flake.nixosModules.services-infrastructure-homepage =
  { config, lib, flakeLib, ... }:
  let
    domain = config.vars.acme.domain;
    net = config.vars.network;
    ip = net.podmanAddresses;
    listenPort = 8082;

    envContent = ''
      HOMEPAGE_VAR_RADARR_KEY=${config.sops.placeholder."media.radarr.api_key"}
      HOMEPAGE_VAR_SONARR_KEY=${config.sops.placeholder."media.sonarr.api_key"}
      HOMEPAGE_VAR_LIDARR_KEY=${config.sops.placeholder."media.lidarr.api_key"}
      HOMEPAGE_VAR_PROWLARR_KEY=${config.sops.placeholder."media.prowlarr.api_key"}
      HOMEPAGE_VAR_BAZARR_KEY=${config.sops.placeholder."media.bazarr.api_key"}
      HOMEPAGE_VAR_SABNZBD_KEY=${config.sops.placeholder."media.sabnzbd.api_key"}
      HOMEPAGE_VAR_JELLYFIN_KEY=${config.sops.placeholder."media.jellyfin.apikeys.seerr"}
      HOMEPAGE_VAR_GRAFANA_USER=${config.sops.placeholder."monitoring.grafana.admin.user"}
      HOMEPAGE_VAR_GRAFANA_PASSWORD=${config.sops.placeholder."monitoring.grafana.admin.password"}
      HOMEPAGE_VAR_SEERR_KEY=${config.sops.placeholder."media.seerr.api_key"}
      HOMEPAGE_VAR_ADGUARD_USER=${config.sops.placeholder."dns.adguard.username"}
      HOMEPAGE_VAR_ADGUARD_PASSWORD=${config.sops.placeholder."dns.adguard.password"}
      HOMEPAGE_VAR_FRIGATE_PASSWORD=${config.sops.placeholder."homepage.frigate_password"}
      HOMEPAGE_VAR_GHOSTFOLIO_TOKEN=${config.sops.placeholder."homepage.ghostfolio_token"}
    '';
  in
  {
    # Most secrets above are already declared elsewhere in this host config
    # (media-mgmt/*.nix, media-play.nix, monitoring.nix) -- placeholders
    # work here without redeclaring sops.secrets for them. frigate_password
    # and ghostfolio_token are homepage-only, so they need their own
    # declarations.
    sops.secrets."homepage.frigate_password" = { };
    # Bearer token from a manual POST to Ghostfolio's own auth API using its
    # account Security Token (see docs/widgets/services/ghostfolio.md
    # upstream) -- expires 2027-02-27. To rotate: grab a fresh Security
    # Token from Ghostfolio's Settings > Account page, then from this host
    # (reaches ip.ghostfolio directly):
    #   curl -s -X POST http://<ip.ghostfolio>:3333/api/v1/auth/anonymous \
    #     -H 'Content-Type: application/json' \
    #     -d '{"accessToken": "<security token>"}'
    # take the `authToken` from the response and:
    #   sops set secrets/secrets.yaml '["homepage.ghostfolio_token"]' '"<authToken>"'
    sops.secrets."homepage.ghostfolio_token" = { };

    # Default owner (root) is fine: EnvironmentFile= is read by systemd
    # itself before the DynamicUser sandboxed process starts, not by the
    # service's own runtime UID.
    sops.templates."homepage.env" = {
      mode = "0400";
      content = envContent;
    };

    services.homepage-dashboard = {
      enable = true;
      listenPort = listenPort;
      allowedHosts = "home.${domain}";
      environmentFiles = [ config.sops.templates."homepage.env".path ];

      settings = {
        title = "sutala";
        theme = "dark";
        headerStyle = "clean";
        color = "slate";
        quicklaunch = {
          searchDescriptions = true;
        };
      };

      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
        {
          datetime = {
            text_size = "xl";
            format = {
              dateStyle = "long";
              timeStyle = "short";
              hourCycle = "h23";
            };
          };
        }
      ];

      services = [
        {
          Media = [
            {
              Jellyfin = {
                description = "Movie & TV streaming";
                icon = "jellyfin.png";
                href = "https://jellyfin.${domain}";
                widget = {
                  type = "jellyfin";
                  url = "http://${net.containers.mediaPlay.localAddress}:8096";
                  key = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
                };
              };
            }
            {
              Seerr = {
                description = "Media requests";
                icon = "overseerr.png";
                href = "https://seerr.${domain}";
                widget = {
                  type = "seerr";
                  url = "http://${ip.seerr}:5055";
                  key = "{{HOMEPAGE_VAR_SEERR_KEY}}";
                };
              };
            }
            {
              Navidrome = {
                # Link-only: its widget needs a Subsonic-style user/token/salt
                # (token = md5(password + salt)), no existing account to reuse.
                description = "Music streaming";
                icon = "navidrome.png";
                href = "https://navidrome.${domain}";
                siteMonitor = "https://navidrome.${domain}";
              };
            }
            {
              Audiobookshelf = {
                # Link-only: its widget needs an API key generated by hand
                # in its own admin UI, not yet in secrets.yaml.
                description = "Audiobook & podcast server";
                icon = "audiobookshelf.png";
                href = "https://audiobookshelf.${domain}";
                siteMonitor = "https://audiobookshelf.${domain}";
              };
            }
            {
              Bookshelf = {
                description = "Book tracking";
                icon = "mdi-book-open-page-variant";
                href = "https://bookshelf.${domain}";
                siteMonitor = "https://bookshelf.${domain}";
              };
            }
          ];
        }
        {
          Acquisition = [
            {
              Radarr = {
                description = "Movie management";
                icon = "radarr.png";
                href = "https://radarr.${domain}";
                widget = {
                  type = "radarr";
                  url = "http://${ip.radarr}:7878";
                  key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
                };
              };
            }
            {
              Sonarr = {
                description = "TV show management";
                icon = "sonarr.png";
                href = "https://sonarr.${domain}";
                widget = {
                  type = "sonarr";
                  url = "http://${ip.sonarr}:8989";
                  key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
                };
              };
            }
            {
              Lidarr = {
                description = "Music management";
                icon = "lidarr.png";
                href = "https://lidarr.${domain}";
                widget = {
                  type = "lidarr";
                  url = "http://${ip.lidarr}:8686";
                  key = "{{HOMEPAGE_VAR_LIDARR_KEY}}";
                };
              };
            }
            {
              Prowlarr = {
                description = "Indexer management";
                icon = "prowlarr.png";
                href = "https://prowlarr.${domain}";
                widget = {
                  type = "prowlarr";
                  url = "http://${ip.prowlarr}:9696";
                  key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
                };
              };
            }
            {
              Bazarr = {
                description = "Subtitle management";
                icon = "bazarr.png";
                href = "https://bazarr.${domain}";
                widget = {
                  type = "bazarr";
                  url = "http://${ip.bazarr}:6767";
                  key = "{{HOMEPAGE_VAR_BAZARR_KEY}}";
                };
              };
            }
            {
              SABnzbd = {
                description = "Usenet downloader";
                icon = "sabnzbd.png";
                href = "https://sabnzbd.${domain}";
                widget = {
                  type = "sabnzbd";
                  url = "http://${ip.sabnzbd}:8080";
                  key = "{{HOMEPAGE_VAR_SABNZBD_KEY}}";
                };
              };
            }
            {
              Maintainerr = {
                description = "Library cleanup automation";
                icon = "maintainerr.png";
                href = "https://maintainerr.${domain}";
                widget = {
                  type = "maintainerr";
                  url = "http://${ip.maintainerr}:6246";
                };
              };
            }
          ];
        }
        {
          Finance = [
            {
              "Actual Budget" = {
                description = "Personal budgeting";
                icon = "actual-budget.png";
                href = "https://actualbudget.${domain}";
                siteMonitor = "https://actualbudget.${domain}";
              };
            }
            {
              Ghostfolio = {
                description = "Investment portfolio tracking";
                icon = "ghostfolio.png";
                href = "https://ghostfolio.${domain}";
                widget = {
                  type = "ghostfolio";
                  url = "http://${ip.ghostfolio}:3333";
                  # Expires 2027-02-27 (see the sops.secrets comment above)
                  # -- re-run the auth exchange and `sops set` before then.
                  key = "{{HOMEPAGE_VAR_GHOSTFOLIO_TOKEN}}";
                };
              };
            }
          ];
        }
        {
          Home = [
            {
              "Home Assistant" = {
                # Link-only: its widget needs a long-lived access token not
                # yet in secrets.yaml (declaring an unset secret breaks the build).
                description = "Home automation hub";
                icon = "home-assistant.png";
                href = "https://ha.${domain}";
                siteMonitor = "https://ha.${domain}";
              };
            }
            {
              Frigate = {
                description = "NVR & object detection";
                icon = "frigate.png";
                href = "https://nvr.${domain}";
                widget = {
                  type = "frigate";
                  url = "http://${net.containers.homeAuto.localAddress}:80";
                  # Dedicated viewer-role Frigate account -- read-only, no
                  # config/settings access even with the credential exposed.
                  username = "homepage";
                  password = "{{HOMEPAGE_VAR_FRIGATE_PASSWORD}}";
                };
              };
            }
            {
              "Zigbee2MQTT" = {
                description = "Zigbee device bridge";
                icon = "zigbee2mqtt.png";
                href = "https://z2m.${domain}";
                siteMonitor = "https://z2m.${domain}";
              };
            }
            {
              "Music Assistant" = {
                description = "Multi-room audio control";
                icon = "music-assistant.png";
                href = "https://ma.${domain}";
                siteMonitor = "https://ma.${domain}";
              };
            }
          ];
        }
        {
          Infra = [
            {
              Grafana = {
                description = "Metrics dashboards";
                icon = "grafana.png";
                href = "https://grafana.${domain}";
                widget = {
                  type = "grafana";
                  version = 2;
                  url = "http://${net.containers.monitoring.localAddress}:3001";
                  username = "{{HOMEPAGE_VAR_GRAFANA_USER}}";
                  password = "{{HOMEPAGE_VAR_GRAFANA_PASSWORD}}";
                };
              };
            }
            {
              Prometheus = {
                description = "Metrics collection";
                icon = "prometheus.png";
                widget = {
                  type = "prometheus";
                  url = "http://${net.containers.monitoring.localAddress}:9090";
                };
              };
            }
            {
              Arcane = {
                # Link-only: its widget needs a scoped API key generated by
                # hand in its own UI, not yet in secrets.yaml.
                description = "Container management";
                icon = "arcane.png";
                href = "https://oci.${domain}";
                siteMonitor = "https://oci.${domain}";
              };
            }
            {
              Authelia = {
                description = "SSO identity provider";
                icon = "authelia.png";
                href = "https://auth.${domain}";
                siteMonitor = "https://auth.${domain}";
              };
            }
            {
              "AdGuard Home" = {
                description = "DNS filtering & ad blocking";
                icon = "adguard-home.png";
                href = "https://dns.${domain}";
                widget = {
                  type = "adguard";
                  url = "https://dns.${domain}";
                  username = "{{HOMEPAGE_VAR_ADGUARD_USER}}";
                  password = "{{HOMEPAGE_VAR_ADGUARD_PASSWORD}}";
                };
              };
            }
            {
              Tailscale = {
                # Link-only: its widget queries Tailscale's own cloud API,
                # needing a manually-generated access token + device ID --
                # no local secret to reuse, and no local URL either.
                description = "Mesh VPN";
                icon = "tailscale.png";
                href = "https://login.tailscale.com/admin/machines";
              };
            }
          ];
        }
      ];
    };

    services.nginx.virtualHosts."home.${domain}" = flakeLib.nginx.mkProxyVhost {
      domain = domain;
      cidrs = net.nginxAllowCidrs;
      upstream = "http://127.0.0.1:${toString listenPort}";
      forwardAuth = true;
    };
  };
}
