{
  flake.nixosModules.containers-media-play =
    {
      config,
      inputs,
      pkgs,
      lib,
      flakeModules,
      flakeLib,
      ...
    }:
    let
      jellyfinSsoAuthXmlContent = ''
        <?xml version="1.0" encoding="utf-8"?>
        <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <SamlConfigs />
          <OidConfigs>
            <item>
              <key>
                <string>authelia</string>
              </key>
              <value>
                <PluginConfiguration>
                  <OidEndpoint>https://auth.${config.vars.acme.domain}</OidEndpoint>
                  <OidClientId>jellyfin</OidClientId>
                  <OidSecret>${config.sops.placeholder."media.jellyfin.oidc_client_secret"}</OidSecret>
                  <Enabled>true</Enabled>
                  <EnableAuthorization>true</EnableAuthorization>
                  <EnableAllFolders>true</EnableAllFolders>
                  <EnabledFolders />
                  <AdminRoles>
                    <string>admin</string>
                  </AdminRoles>
                  <Roles>
                    <string>admin</string>
                    <string>family</string>
                  </Roles>
                  <EnableFolderRoles>false</EnableFolderRoles>
                  <EnableLiveTvRoles>false</EnableLiveTvRoles>
                  <EnableLiveTv>false</EnableLiveTv>
                  <EnableLiveTvManagement>false</EnableLiveTvManagement>
                  <LiveTvRoles />
                  <LiveTvManagementRoles />
                  <FolderRoleMappings />
                  <RoleClaim>groups</RoleClaim>
                  <OidScopes>
                    <string>groups</string>
                  </OidScopes>
                  <CanonicalLinks></CanonicalLinks>
                  <DisableHttps>false</DisableHttps>
                  <DisablePushedAuthorization>true</DisablePushedAuthorization>
                  <DoNotValidateEndpoints>false</DoNotValidateEndpoints>
                  <DoNotValidateIssuerName>false</DoNotValidateIssuerName>
                  <SchemeOverride>https</SchemeOverride>
                </PluginConfiguration>
              </value>
            </item>
          </OidConfigs>
        </PluginConfiguration>
      '';
      # No secret values embedded (placeholders are stable tokens) — see
      # authelia.nix's configHash.
      jellyfinSsoAuthXmlHash = builtins.hashString "sha256" jellyfinSsoAuthXmlContent;

      languageMix = language: {
        all = [ { is = { inherit language; }; } ];
        sort = "random";
        limit = 200;
      };
      mix = rule: {
        all = [ rule ];
        sort = "random";
        limit = 200;
      };
      pathMix = path: mix { contains.filepath = path; };
      genreMix = genres: mix { any = map (genre: { is = { inherit genre; }; }) genres; };
      navidromeSmartPlaylists = {
        "Carnatic Mix" = pathMix "Classical/Carnatic/";
        "Hindustani Mix" = pathMix "Classical/Hindustani/";
        "Western Classical Mix" = pathMix "Classical/Western/";
        "Classical Instrumental" = genreMix [
          "Instrumental"
          "Concerto"
          "Symphony"
          "Sonata"
        ];
        "Opera & Choral" = genreMix [
          "Opera"
          "Requiem"
          "Mass"
        ];
        "Rock" = genreMix [
          "Rock"
          "Hard Rock"
          "Alternative Rock"
          "Soft Rock"
          "Post-Grunge"
        ];
        "Metal & Punk" = genreMix [
          "Heavy Metal"
          "Punk Rock"
          "Pop Punk"
        ];
        "Pop & Dance" = genreMix [
          "Pop"
          "Dance-Pop"
          "Europop"
          "Synth-Pop"
          "Teen Pop"
        ];
        "Disco & House" = genreMix [
          "Disco"
          "Euro-Disco"
          "House"
        ];
        "Hip Hop & R&B" = genreMix [
          "Hip Hop"
          "Contemporary R&B"
        ];
        "Jazz & Blues" = genreMix [
          "Jazz"
          "Blues"
        ];
        "Chill" = genreMix [
          "Easy Listening"
          "Ballad"
          "Soft Rock"
        ];
        "Throwback 90s-00s" = {
          all = [
            {
              inTheRange.year = [
                1990
                2009
              ];
            }
          ];
          sort = "random";
          limit = 200;
        };
        "Devotional Mix" = pathMix "Devotional/";
        "Malayalam Devotional" = {
          all = [
            { contains.filepath = "Devotional/"; }
            { is.language = "mal"; }
          ];
          sort = "random";
          limit = 200;
        };
        "Tamil Devotional" = {
          all = [
            { contains.filepath = "Devotional/"; }
            { is.language = "tam"; }
          ];
          sort = "random";
          limit = 200;
        };
        "Sanskrit Stotras" = {
          all = [
            { contains.filepath = "Devotional/"; }
            { is.language = "san"; }
          ];
          sort = "random";
          limit = 200;
        };
        "Hindi Mix" = languageMix "hin";
        "Tamil Mix" = languageMix "tam";
        "Malayalam Mix" = languageMix "mal";
        "Recently Added" = {
          all = [ { inTheLast.dateAdded = 30; } ];
          sort = "dateAdded";
          order = "desc";
          limit = 100;
        };
        "Discovery" = {
          all = [ { is.playCount = 0; } ];
          sort = "random";
          limit = 100;
        };
        "Favourites" = {
          all = [ { is.loved = true; } ];
          sort = "dateLoved";
          order = "desc";
        };
        "Heavy Rotation" = {
          all = [
            { gt.playCount = 0; }
            { inTheLast.lastPlayed = 90; }
          ];
          sort = "playCount";
          order = "desc";
          limit = 100;
        };
      };
      navidromePlaylistsDir = pkgs.linkFarm "navidrome-smart-playlists" (
        lib.mapAttrsToList (name: rules: {
          name = "${name}.nsp";
          path = pkgs.writeText "${name}.nsp" (builtins.toJSON ({ inherit name; } // rules));
        }) navidromeSmartPlaylists
      );
    in
    {
      # Host group for media files
      users.groups.media = {
        gid = 2000;
      };

      # Host storage for media-play container
      systemd.tmpfiles.rules = lib.mkMerge [
        [
          "d /srv/appdata/media-play 2770 root media - -"
        ]
        (lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) [
          "d /srv/appdata/media-play/jellyfin 2770 root media - -"
        ])
        (lib.mkIf (config.containers.media-play.config.services.navidrome.enable or false) [
          "d /srv/appdata/media-play/navidrome 2770 root media - -"
        ])
      ];

      # Host nginx reverse proxies for media-play container
      services.nginx.virtualHosts."jellyfin.${config.vars.acme.domain}" =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          (
            lib.recursiveUpdate (flakeLib.nginx.mkProxyVhost {
              domain = config.vars.acme.domain;
              cidrs = config.vars.network.nginxAllowCidrs;
              upstream = "http://${config.vars.network.containers.mediaPlay.localAddress}:8096";
            }) { locations."/metrics".return = "404"; }
          );

      services.nginx.virtualHosts."navidrome.${config.vars.acme.domain}" =
        lib.mkIf (config.containers.media-play.config.services.navidrome.enable or false)
          (
            flakeLib.nginx.mkProxyVhost {
              domain = config.vars.acme.domain;
              cidrs = config.vars.network.nginxAllowCidrs;
              upstream = "http://${config.vars.network.containers.mediaPlay.localAddress}:4533";
            }
          );

      # Host firewall for media-play container
      networking.firewall = {
        interfaces = {
          ve-media-play = {
            allowedTCPPorts = [
              53 # DNS (if a resolver is enabled in the container)
              443 # Jellyfin's SSO plugin calls auth.${domain} directly
              4533 # Navidrome
              8096 # Jellyfin
              9100 # node-exporter
            ];
            allowedUDPPorts = [
              53 # DNS (if a resolver is enabled in the container)
              7359 # Jellyfin client discovery
            ];
          };
        };
      };

      containers.media-play = (
        {
          autoStart = true;
          specialArgs = {
            inherit inputs flakeModules;
            domain = config.vars.acme.domain;
            monitoringLocalAddress = config.vars.network.containers.monitoring.localAddress;
          };
        }
        // flakeLib.container-definition.mkContainerNetwork {
          hostAddress = config.vars.network.containers.mediaPlay.hostAddress;
          localAddress = config.vars.network.containers.mediaPlay.localAddress;
        }
        // {
          config = {
            imports = [
              flakeModules.nixos.services-system-nix-defaults-nixos
              flakeModules.nixos.containers-common
              inputs.declarative-jellyfin.nixosModules.default
              flakeModules.nixos.services-media-players-default
            ];

            nixpkgs.overlays = [
              inputs.self.overlays.default
            ];

            # Containers re-evaluate their own nixpkgs.config and don't inherit the
            # host's (only nixpkgs.hostPlatform is inherited) -- this must be
            # restated here, not just in modules/hardware/intel-igpu.nix, or
            # hardware.graphics.extraPackages below fails to evaluate.
            nixpkgs.config.permittedInsecurePackages = [
              "intel-media-sdk-23.2.2"
            ];

            networking = {
              hostName = "media-play";
              defaultGateway = config.vars.network.containers.mediaPlay.hostAddress;
              nameservers = [ config.vars.network.lanIp ];
              # Routes OIDC calls to auth.${domain} via the veth gateway — see
              # life/ghostfolio.nix's addHosts for why.
              extraHosts = ''
                ${config.vars.network.containers.mediaPlay.hostAddress} auth.${config.vars.acme.domain}
              '';
              firewall.allowedTCPPorts = [
                4533 # Navidrome
                8096 # Jellyfin
                9100 # node-exporter
              ];
              firewall.allowedUDPPorts = [
                7359 # Jellyfin client discovery
              ];
            };

            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-compute-runtime-legacy1
                intel-media-driver
                # intel-vaapi-driver
                level-zero
                intel-media-sdk
              ];
            };
            systemd.tmpfiles.rules = [
              "z /var/lib/jellyfin/log 0750 jellyfin jellyfin - -"
              "z /var/lib/jellyfin/logs 0750 jellyfin jellyfin - -"
              "Z /var/lib/jellyfin/log/*.log 0640 jellyfin jellyfin - -"
              "Z /var/lib/jellyfin/log/*.txt 0640 jellyfin jellyfin - -"
              "Z /var/lib/jellyfin/logs/*.log 0640 jellyfin jellyfin - -"
              "Z /var/lib/jellyfin/logs/*.txt 0640 jellyfin jellyfin - -"
            ];

            # Jellyfin only reads SSO-Auth.xml at startup; nothing else here
            # would trigger a restart on content-only changes.
            systemd.services.jellyfin.restartTriggers = [ jellyfinSsoAuthXmlHash ];

            # Sized from ~21h process-exporter peaks + safety margin.
            systemd.services.jellyfin.serviceConfig = {
              MemoryMax = "1024M";
              CPUQuota = "100%";
              # Replaces declarative-jellyfin's own ExecStartPre, which chmod/chowns the whole dataDir and always errors on SSO-Auth.xml (bind-mounted read-only here).
              ExecStartPre = lib.mkForce (
                "+"
                + pkgs.writeShellScript "jellyfin-perm-fix" ''
                  find "${config.services.jellyfin.dataDir}" -path "${config.services.jellyfin.dataDir}/plugins/configurations/SSO-Auth.xml" -prune -o -exec chown ${config.services.jellyfin.user}:${config.services.jellyfin.group} {} +
                  find "${config.services.jellyfin.dataDir}" -path "${config.services.jellyfin.dataDir}/plugins/configurations/SSO-Auth.xml" -prune -o -exec chmod 750 {} +
                  chown -R ${config.services.jellyfin.user}:${config.services.jellyfin.group} ${config.services.jellyfin.cacheDir}
                  chmod -R 750 ${config.services.jellyfin.cacheDir}
                ''
              );
            };
            services.navidrome.settings.PlaylistsPath = "playlists";
            systemd.services.navidrome.serviceConfig = {
              MemoryMax = "384M";
              CPUQuota = "100%";
            };
            systemd.services.alloy.serviceConfig = {
              MemoryMax = "512M";
              CPUQuota = "100%";
            };
          };
          bindMounts = {
            "/etc/localtime" = {
              hostPath = "/etc/localtime";
              isReadOnly = true;
            };
            "/dev/dri" = {
              hostPath = "/dev/dri";
              isReadOnly = false;
            };
            "/data" = {
              hostPath = "/srv/media";
              isReadOnly = false;
            };
            "/var/lib/jellyfin" = {
              hostPath = "/srv/appdata/media-play/jellyfin";
              isReadOnly = false;
            };
            "/var/lib/navidrome" = {
              hostPath = "/srv/appdata/media-play/navidrome";
              isReadOnly = false;
            };
            "/data/library/music/playlists" = {
              hostPath = "${navidromePlaylistsDir}";
              isReadOnly = true;
            };

            "/run/secrets/media.jellyfin.users.kra3.password" = {
              hostPath = "/run/secrets/media.jellyfin.users.kra3.password";
              isReadOnly = true;
            };
            "/run/secrets/media.jellyfin.users.home.password" = {
              hostPath = "/run/secrets/media.jellyfin.users.home.password";
              isReadOnly = true;
            };
            "/run/secrets/media.jellyfin.apikeys.seerr" = {
              hostPath = "/run/secrets/media.jellyfin.apikeys.seerr";
              isReadOnly = true;
            };
            "/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml" = {
              hostPath = config.sops.templates."media-play/jellyfin-sso-auth.xml".path;
              isReadOnly = true;
            };
          };
          allowedDevices = [
            {
              node = "/dev/dri/card1";
              modifier = "rw";
            }
            {
              node = "/dev/dri/renderD128";
              modifier = "rw";
            }
          ];
        }
      );

      systemd.services."container@media-play" = flakeLib.container-definition.mkContainerSystemdDeps [ ];

      # Create jellyfin group on host matching container GID for secret access.
      # Also reused by monitoring.nix's grafana secrets (coincidentally the same
      # gid 999) — don't disable declarative-jellyfin without checking that.
      users.groups.jellyfin =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          {
            gid = 999;
          };

      sops.secrets."media.jellyfin.users.kra3.password" =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          {
            mode = "0440";
            group = "jellyfin";
          };
      sops.secrets."media.jellyfin.users.home.password" =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          {
            mode = "0440";
            group = "jellyfin";
          };
      sops.secrets."media.jellyfin.apikeys.seerr" =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          {
            mode = "0440";
            group = "jellyfin";
          };

      sops.secrets."media.jellyfin.oidc_client_secret" =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          { };

      # Plugin install itself is still manual (Dashboard -> Plugins ->
      # Catalog); its provider config is pre-seeded here so nothing else is.
      sops.templates."media-play/jellyfin-sso-auth.xml" =
        lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false)
          {
            owner = "root";
            group = "root";
            mode = "0444";
            content = jellyfinSsoAuthXmlContent;
          };
    };
}
