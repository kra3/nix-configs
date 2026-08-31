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
    '';
  in
  {
    # These secrets are already declared elsewhere in this host config
    # (media-mgmt/*.nix, media-play.nix, monitoring.nix) -- placeholders
    # work here without redeclaring sops.secrets for them.

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
        # No built-in "color" value matches Catppuccin -- customCSS below
        # defines a .theme-catppuccin class to back this.
        color = "catppuccin";
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

      # Catppuccin Mocha (catppuccin.com/palette), mapped onto Homepage's
      # own 50-900 --color-* scale (src/styles/theme.css upstream) so every
      # place that scale is used (cards, borders, the dark-mode page
      # background at --color-800) picks it up, not just hardcoded overrides.
      customCSS = ''
        .theme-catppuccin {
          --color-50: 205 214 244;   /* text */
          --color-100: 186 194 222;  /* subtext1 */
          --color-200: 166 173 200;  /* subtext0 */
          --color-300: 147 153 178;  /* overlay2 */
          --color-400: 127 132 156;  /* overlay1 */
          --color-500: 108 112 134;  /* overlay0 */
          --color-600: 88 91 112;    /* surface2 */
          --color-700: 69 71 90;     /* surface1 */
          --color-800: 30 30 46;     /* base -- dark-mode page background */
          --color-900: 17 17 27;     /* crust */
          --color-logo-start: 203 166 247; /* mauve */
          --color-logo-stop: 180 190 254;  /* lavender */
        }
      '';

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
                siteMonitor = "https://seerr.${domain}";
              };
            }
            {
              Navidrome = {
                description = "Music streaming";
                icon = "navidrome.png";
                href = "https://navidrome.${domain}";
                siteMonitor = "https://navidrome.${domain}";
              };
            }
            {
              Audiobookshelf = {
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
                siteMonitor = "https://maintainerr.${domain}";
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
                siteMonitor = "https://ghostfolio.${domain}";
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
                # Link-only: Frigate's own built-in auth (enabled by default,
                # no forwardAuth in front of it -- see surveillance/proxy.nix)
                # 401s the widget's unauthenticated call; needs an admin
                # username/password added to secrets.yaml before going live.
                description = "NVR & object detection";
                icon = "frigate.png";
                href = "https://nvr.${domain}";
                siteMonitor = "https://nvr.${domain}";
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
