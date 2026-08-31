{
  flake.nixosModules.containers-media-play = { config, inputs, pkgs, lib, flakeModules, flakeLib, ... }:
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
    services.nginx.virtualHosts."jellyfin.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) (
      flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${config.vars.network.containers.mediaPlay.localAddress}:8096";
      }
    );

    services.nginx.virtualHosts."navidrome.${config.vars.acme.domain}" = lib.mkIf (config.containers.media-play.config.services.navidrome.enable or false) (
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

    containers.media-play = ({
      autoStart = true;
      specialArgs = {
        inherit inputs flakeModules;
        domain = config.vars.acme.domain;
        monitoringLocalAddress = config.vars.network.containers.monitoring.localAddress;
      };
    } // flakeLib.container-definition.mkContainerNetwork {
      hostAddress = config.vars.network.containers.mediaPlay.hostAddress;
      localAddress = config.vars.network.containers.mediaPlay.localAddress;
    } // {
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
    });

    systemd.services."container@media-play" =
      flakeLib.container-definition.mkContainerSystemdDeps [ ];

    # Create jellyfin group on host matching container GID for secret access.
    # Also reused by monitoring.nix's grafana secrets (coincidentally the same
    # gid 999) — don't disable declarative-jellyfin without checking that.
    users.groups.jellyfin = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
      gid = 999;
    };

    sops.secrets."media.jellyfin.users.kra3.password" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
      mode = "0440";
      group = "jellyfin";
    };
    sops.secrets."media.jellyfin.users.home.password" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
      mode = "0440";
      group = "jellyfin";
    };
    sops.secrets."media.jellyfin.apikeys.seerr" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
      mode = "0440";
      group = "jellyfin";
    };

    sops.secrets."media.jellyfin.oidc_client_secret" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) { };

    # Plugin install itself is still manual (Dashboard -> Plugins ->
    # Catalog); its provider config is pre-seeded here so nothing else is.
    sops.templates."media-play/jellyfin-sso-auth.xml" = lib.mkIf (config.containers.media-play.config.services.declarative-jellyfin.enable or false) {
      owner = "root";
      group = "root";
      mode = "0444";
      content = jellyfinSsoAuthXmlContent;
    };
  };
}
