{
  config,
  lib,
  pkgs,
  ...
}:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.home-auto;
  macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
in
{
  virtualisation.quadlet.containers.home-assistant = {
    containerConfig = {
      image = "ghcr.io/home-assistant/home-assistant:2026.7.2";
      publishPorts = [ "127.0.0.1:8123:8123" ];
      networks = [
        "${network.ref}:ip=10.3.2.10"
        "${macvlan.ref}:ip=192.168.1.33,mac=02:42:c0:a8:01:21"
      ];
      dns = [ "10.3.2.1" ];
      logDriver = "journald";
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
      ];
      environments = {
        TZ = "Europe/Stockholm";
        DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
      };
      volumes = [
        "/srv/appdata/home-auto/home-assistant/data:/config"
        "${./ha-config/configuration.yaml}:/config/configuration.yaml:ro"
        "${./ha-config/automations.yaml}:/config/automations.yaml:ro"
        "${./ha-config/lovelace.yaml}:/config/lovelace.yaml:ro"
        "${./ha-config/dashboards}:/config/dashboards:ro"
        "${./ha-config/packages}:/config/packages:ro"
        "${./ha-config/blueprints}:/config/blueprints:ro"
        "${./ha-config/scripts.yaml}:/config/scripts.yaml:ro"
        "${./ha-config/scenes.yaml}:/config/scenes.yaml:ro"
        "${config.sops.templates."home-assistant/secrets.yaml".path}:/config/secrets.yaml:ro"
        "/run/dbus:/run/dbus:ro"
      ];
      addCapabilities = [
        "NET_ADMIN"
        "NET_RAW"
      ];
    };
    unitConfig = {
      After = [
        "home-auto-network.service"
        "home-auto-macvlan-network.service"
      ];
      Requires = [
        "home-auto-network.service"
        "home-auto-macvlan-network.service"
      ];
    };
    serviceConfig = {
      Restart = "always";
    };
  };

  environment.etc."alloy/home-assistant.alloy".text = ''
    loki.source.journal "home_assistant" {
      matches = "_SYSTEMD_UNIT=home-assistant.service"
      labels = {
        job = "home-assistant",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."ha.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = ''
      ${allowBlock}
      client_max_body_size 500m;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
      '';
    };
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
}
