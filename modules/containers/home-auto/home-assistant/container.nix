{
  flake.nixosModules.containers-home-auto-home-assistant-container = {
    config,
    flakeLib,
    flakeModules,
    ...
  }:
  let
    network = config.virtualisation.quadlet.networks.home-auto;
    macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
  in
  {
    imports = [ flakeModules.nixos.services-home-automation-home-assistant ];

    virtualisation.quadlet.containers.home-assistant = {
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
          "${../../../services/home-automation/home-assistant/ha-config/scripts.yaml}:/config/scripts.yaml:ro"
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
        healthCmd = "python3 -c \"import urllib.request as u; u.urlopen('http://localhost:8123/manifest.json', timeout=5)\"";
        healthInterval = "1m";
        healthRetries = 3;
        healthStartPeriod = "2m";
        healthTimeout = "10s";
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
    };

    services.nginx.virtualHosts."ha.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:8123";
      vhostExtraConfig = "client_max_body_size 500m;";
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
      '';
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
  };
}
