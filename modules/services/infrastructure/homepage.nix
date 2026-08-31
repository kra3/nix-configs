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
      HOMEPAGE_VAR_BOOKSHELF_KEY=${config.sops.placeholder."media.bookshelf.api_key"}
      HOMEPAGE_VAR_GRAFANA_USER=${config.sops.placeholder."monitoring.grafana.admin.user"}
      HOMEPAGE_VAR_GRAFANA_PASSWORD=${config.sops.placeholder."monitoring.grafana.admin.password"}
      HOMEPAGE_VAR_SEERR_KEY=${config.sops.placeholder."media.seerr.api_key"}
      HOMEPAGE_VAR_ADGUARD_USER=${config.sops.placeholder."dns.adguard.username"}
      HOMEPAGE_VAR_ADGUARD_PASSWORD=${config.sops.placeholder."homepage.adguard_password"}
      HOMEPAGE_VAR_FRIGATE_PASSWORD=${config.sops.placeholder."homepage.frigate_password"}
      HOMEPAGE_VAR_GHOSTFOLIO_TOKEN=${config.sops.placeholder."homepage.ghostfolio_token"}
      HOMEPAGE_VAR_TAILSCALE_KEY=${config.sops.placeholder."homepage.tailscale_key"}
      HOMEPAGE_VAR_TAILSCALE_DEVICE_ID=${config.sops.placeholder."homepage.tailscale_device_id"}
      HOMEPAGE_VAR_HOMEASSISTANT_TOKEN=${config.sops.placeholder."homepage.homeassistant_token"}
      HOMEPAGE_VAR_ARCANE_KEY=${config.sops.placeholder."homepage.arcane_key"}
      HOMEPAGE_VAR_NAVIDROME_TOKEN=${config.sops.placeholder."homepage.navidrome_token"}
      HOMEPAGE_VAR_NAVIDROME_SALT=${config.sops.placeholder."homepage.navidrome_salt"}
      HOMEPAGE_VAR_AUDIOBOOKSHELF_KEY=${config.sops.placeholder."homepage.audiobookshelf_key"}
    '';
  in
  {
    # frigate_password/ghostfolio_token/tailscale_* are homepage-only; the rest reuse secrets declared elsewhere.
    sops.secrets."homepage.frigate_password" = { };
    # Bearer token via Ghostfolio's Security Token -> POST /api/v1/auth/anonymous exchange; expires 2027-02-27.
    sops.secrets."homepage.ghostfolio_token" = { };
    sops.secrets."homepage.tailscale_key" = { };
    sops.secrets."homepage.tailscale_device_id" = { };
    sops.secrets."homepage.adguard_password" = { };
    sops.secrets."homepage.homeassistant_token" = { };
    sops.secrets."homepage.arcane_key" = { };
    sops.secrets."homepage.navidrome_token" = { };
    sops.secrets."homepage.navidrome_salt" = { };
    sops.secrets."homepage.audiobookshelf_key" = { };

    # restartUnits: EnvironmentFile= points at a stable path sops-nix rewrites in place, so without this a secret-value-only rotation never restarts the service.
    sops.templates."homepage.env" = {
      mode = "0400";
      content = envContent;
      restartUnits = [ "homepage-dashboard.service" ];
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
        statusStyle = "dot";
        quicklaunch = {
          searchDescriptions = true;
        };
        layout = {
          Media = {
            style = "row";
            columns = 2;
            Play = {
              style = "row";
              columns = 2;
            };
            Acquisition = {
              style = "row";
              columns = 4;
            };
          };
          Finance = {
            style = "row";
            columns = 2;
          };
          Home = {
            style = "row";
            columns = 2;
          };
          Infra = {
            style = "row";
            columns = 3;
          };
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
              Play = [
                {
                  Jellyfin = {
                    description = "Movie & TV streaming";
                    icon = "jellyfin.png";
                    href = "https://jellyfin.${domain}";
                    siteMonitor = "https://jellyfin.${domain}";
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
                    widget = {
                      type = "seerr";
                      url = "http://${ip.seerr}:5055";
                      key = "{{HOMEPAGE_VAR_SEERR_KEY}}";
                    };
                  };
                }
                {
                  Navidrome = {
                    description = "Music streaming";
                    icon = "navidrome.png";
                    href = "https://navidrome.${domain}";
                    siteMonitor = "https://navidrome.${domain}";
                    widget = {
                      type = "navidrome";
                      url = "http://${net.containers.mediaPlay.localAddress}:4533";
                      user = "homepage";
                      token = "{{HOMEPAGE_VAR_NAVIDROME_TOKEN}}";
                      salt = "{{HOMEPAGE_VAR_NAVIDROME_SALT}}";
                    };
                  };
                }
                {
                  Audiobookshelf = {
                    description = "Audiobook & podcast server";
                    icon = "audiobookshelf.png";
                    href = "https://audiobookshelf.${domain}";
                    siteMonitor = "https://audiobookshelf.${domain}";
                    widget = {
                      type = "audiobookshelf";
                      url = "http://${ip.audiobookshelf}:80";
                      key = "{{HOMEPAGE_VAR_AUDIOBOOKSHELF_KEY}}";
                    };
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
                    siteMonitor = "https://radarr.${domain}";
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
                    siteMonitor = "https://sonarr.${domain}";
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
                    siteMonitor = "https://lidarr.${domain}";
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
                    siteMonitor = "https://prowlarr.${domain}";
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
                    siteMonitor = "https://bazarr.${domain}";
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
                    siteMonitor = "https://sabnzbd.${domain}";
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
                    widget = {
                      type = "maintainerr";
                      url = "http://${ip.maintainerr}:6246";
                    };
                  };
                }
                {
                  Bookshelf = {
                    description = "Book tracking";
                    icon = "mdi-book-open-page-variant";
                    href = "https://bookshelf.${domain}";
                    siteMonitor = "https://bookshelf.${domain}";
                    widget = {
                      type = "readarr";
                      url = "http://${ip.bookshelf}:8787";
                      key = "{{HOMEPAGE_VAR_BOOKSHELF_KEY}}";
                    };
                  };
                }
              ];
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
                widget = {
                  type = "ghostfolio";
                  url = "http://${ip.ghostfolio}:3333";
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
                description = "Home automation hub";
                icon = "home-assistant.png";
                href = "https://ha.${domain}";
                siteMonitor = "https://ha.${domain}";
                widget = {
                  type = "homeassistant";
                  url = "http://127.0.0.1:8123";
                  key = "{{HOMEPAGE_VAR_HOMEASSISTANT_TOKEN}}";
                };
              };
            }
            {
              Frigate = {
                description = "NVR & object detection";
                icon = "frigate.png";
                href = "https://nvr.${domain}";
                siteMonitor = "https://nvr.${domain}";
                widget = {
                  type = "frigate";
                  url = "http://${net.containers.homeAuto.localAddress}:80";
                  # Dedicated viewer-role account, no config/settings access.
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
                siteMonitor = "https://grafana.${domain}";
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
                siteMonitor = "http://${net.containers.monitoring.localAddress}:9090";
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
                widget = {
                  type = "arcane";
                  url = "http://127.0.0.1:3552";
                  env = 0;
                  key = "{{HOMEPAGE_VAR_ARCANE_KEY}}";
                };
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
                siteMonitor = "https://dns.${domain}";
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
                description = "Mesh VPN";
                icon = "tailscale.png";
                href = "https://login.tailscale.com/admin/machines";
                siteMonitor = "https://login.tailscale.com/admin/machines";
                widget = {
                  type = "tailscale";
                  deviceid = "{{HOMEPAGE_VAR_TAILSCALE_DEVICE_ID}}";
                  key = "{{HOMEPAGE_VAR_TAILSCALE_KEY}}";
                };
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
