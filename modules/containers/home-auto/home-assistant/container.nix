{
  flake.nixosModules.containers-home-auto-home-assistant-container =
    {
      config,
      flakeLib,
      flakeModules,
      lib,
      pkgs,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.home-auto;
      macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
    in
    {
      imports = [ flakeModules.nixos.services-home-automation-home-assistant ];

      virtualisation.quadlet.containers.home-assistant =
        lib.recursiveUpdate
          (
            {
              containerConfig = {
                networks = [
                  "${network.ref}:ip=10.3.2.10"
                  "${macvlan.ref}:ip=192.168.1.33,mac=02:42:c0:a8:01:21"
                ];
                dns = [ "10.3.2.1" ];
                # Bypasses macvlan isolation by forcing host domains to the bridge gateway
                addHosts = [
                  "ma.${config.vars.acme.domain}:10.3.2.1"
                  "jellyfin.${config.vars.acme.domain}:10.3.2.1"
                  "navidrome.${config.vars.acme.domain}:10.3.2.1"
                  "dns.${config.vars.acme.domain}:10.3.2.1"
                  "nvr.${config.vars.acme.domain}:10.3.2.1"
                  "mqtt.${config.vars.acme.domain}:10.3.2.1"
                  "ht:192.168.1.75"
                  "home-theater:192.168.1.75"
                  "radarr.${config.vars.acme.domain}:10.3.2.1"
                  "sonarr.${config.vars.acme.domain}:10.3.2.1"
                  "sabnzbd.${config.vars.acme.domain}:10.3.2.1"
                  "seerr.${config.vars.acme.domain}:10.3.2.1"
                  "auth.${config.vars.acme.domain}:10.3.2.1"
                ];
                volumes = [
                  "/srv/appdata/home-auto/home-assistant/data:/config"
                  "${../../../services/home-automation/home-assistant/ha-config/configuration.yaml}:/config/configuration.yaml:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/automations}:/config/automations:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/lovelace.yaml}:/config/lovelace.yaml:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/dashboards}:/config/dashboards:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/packages}:/config/packages:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/blueprints}:/config/blueprints:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/custom_templates}:/config/custom_templates:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/scripts.yaml}:/config/scripts.yaml:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/health-metric-card.js}:/config/www/health-metric-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/download-control-card.js}:/config/www/download-control-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/home-hero-card.js}:/config/www/home-hero-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/popup-tile-card.js}:/config/www/popup-tile-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/room-tile-card.js}:/config/www/room-tile-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/status-row-card.js}:/config/www/status-row-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/scene-picker-card.js}:/config/www/scene-picker-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/mode-switch-card.js}:/config/www/mode-switch-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/comfort-card.js}:/config/www/comfort-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/maintenance-cards.js}:/config/www/maintenance-cards.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/climate-room-card.js}:/config/www/climate-room-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/security-status-card.js}:/config/www/security-status-card.js:ro"
                  "${../../../services/home-automation/home-assistant/ha-config/www/security-plan-card.js}:/config/www/security-plan-card.js:ro"
                  "${config.sops.secrets."home-assistant/floorplan.png".path}:/config/www/floorplan.png:ro"
                  "${config.sops.templates."home-assistant/secrets.yaml".path}:/config/secrets.yaml:ro"
                  "/run/dbus:/run/dbus:ro"
                ];
                addCapabilities = [
                  "NET_ADMIN"
                  "NET_RAW"
                ];
                # Safety ceiling, not a tuned limit — bounds a runaway integration
                # (BLE reconnect storms, etc.) so it can't starve the host.
                memory = "2g";
                podmanArgs = [ "--cpus=2" ];
                stopTimeout = 60;
                # Retries internally so podman's immediate first probe (before HA's port is up) doesn't fail nixos-rebuild switch.
                healthCmd = "i=0; while [ $i -lt 12 ]; do python3 -c \"import urllib.request as u; u.urlopen('http://localhost:8123/manifest.json', timeout=2)\" && exit 0; sleep 2; i=$((i+1)); done; exit 1";
                healthInterval = "1m";
                healthRetries = 3;
                healthStartPeriod = "2m";
                healthTimeout = "55s";
              };
            }
            // flakeLib.quadlet.mkNetworkDeps {
              networkServices = [
                "home-auto-network.service"
                "home-auto-macvlan-network.service"
              ];
            }
          )
          {
            # Watchman skips files whose mtime is older than its last scan and Nix store files never change, so drop its parse cache on every start.
            serviceConfig.ExecStartPre = [
              "${pkgs.coreutils}/bin/rm -f /srv/appdata/home-auto/home-assistant/data/.storage/watchman_v2.db /srv/appdata/home-auto/home-assistant/data/.storage/watchman_v2.db-wal /srv/appdata/home-auto/home-assistant/data/.storage/watchman_v2.db-shm"
            ];
          };

      services.nginx.virtualHosts."ha.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://127.0.0.1:8123";
        vhostExtraConfig = ''
          client_max_body_size 500m;
          rewrite ^/api/frigate/([^/]+)/var/lib/frigate/(.*)$ /api/frigate/$1/$2 last;
        '';
        locationExtraConfig = ''
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
        '';
      };

      # TCP proxy so HA pod (and any host-side client) can reach mosquitto in nspawn home-auto
      # via the bridge gw 10.3.2.1:1883 — same pattern as *arr nginx vhosts.
      # LAN clients reach mosquitto via existing DNAT on lanIf (sutala/configuration.nix forwardPorts);
      # those packets are rewritten in PREROUTING and never hit this listener.
      services.nginx.streamConfig = ''
        server {
          listen 1883;
          proxy_pass ${config.vars.network.containers.homeAuto.localAddress}:1883;
          proxy_timeout 1h;
        }
      '';

      sops.templates."home-assistant/secrets.yaml" = {
        owner = "root";
        group = "root";
        mode = "0444";
        content = ''
          homeassistant_latitude: ${config.sops.placeholder."homeassistant.latitude"}
          homeassistant_longitude: ${config.sops.placeholder."homeassistant.longitude"}
          mosquitto_pwd: ${config.sops.placeholder."mqtt.password"}
          alarm_code: ${config.sops.placeholder."homeassistant.alarm_code"}
        ''
        + lib.optionalString config.vars.localMedia.enable ''
          radarr_api_key: ${config.sops.placeholder."media.radarr.api_key"}
          sonarr_api_key: ${config.sops.placeholder."media.sonarr.api_key"}
          jellyfin_auth_header: 'MediaBrowser Token="${
            config.sops.placeholder."media.jellyfin.apikeys.seerr"
          }"'
        '';
      };

      sops.secrets."home-assistant/floorplan.png" = {
        sopsFile = ../../../../secrets/floorplan.png;
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0444";
      };

      sops.secrets."homeassistant.latitude" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      sops.secrets."homeassistant.longitude" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      sops.secrets."homeassistant.alarm_code" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # No bind-mount: pasted by hand into the hass-oidc-auth integration's UI.
      sops.secrets."homeassistant.oidc_client_secret" = { };

      # No bind-mount: pasted by hand into the OpenWeatherMap integration's UI
      # (config-flow only, YAML setup was removed upstream) -- kept here as an
      # encrypted backup of the key.
      sops.secrets."homeassistant.openweathermap_api_key" = { };
    };
}
