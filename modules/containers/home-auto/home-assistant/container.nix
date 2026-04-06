{ config, lib, pkgs, ... }:
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
      image = "ghcr.io/home-assistant/home-assistant:2026.4.1";
      publishPorts = [ "127.0.0.1:8123:8123" ];
      networks = [
        "${network.ref}:ip=10.3.2.10"
        "${macvlan.ref}:ip=192.168.1.33,mac=02:42:c0:a8:01:21"
      ];
      logDriver = "journald";
      environments = {
        TZ = "Europe/Stockholm";
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
      addCapabilities = [ "NET_ADMIN" "NET_RAW" ];
    };
    unitConfig = {
      After = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
      Requires = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
    };
    serviceConfig = {
      Restart = "always";
      # macvlan cannot reach parent interface's IP (192.168.1.10).
      # Route host traffic via the Podman bridge gateway instead.
      ExecStartPost = "${pkgs.podman}/bin/podman exec home-assistant ip route add ${config.vars.network.lanIp}/32 via 10.3.2.1";
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

  services.nginx.virtualHosts."ha2.${config.vars.acme.domain}" = {
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

  sops.templates."home-assistant/secrets.yaml" = {
    owner = "root";
    group = "root";
    mode = "0444";
    content = ''
      homeassistant_latitude: ${config.sops.placeholder."homeassistant.latitude"}
      homeassistant_longitude: ${config.sops.placeholder."homeassistant.longitude"}
      mosquitto_pwd: ${config.sops.placeholder."mqtt.password"}
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
}
