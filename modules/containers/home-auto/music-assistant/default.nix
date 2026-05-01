{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.home-auto;
in
{
  virtualisation.quadlet.containers.music-assistant = {
    containerConfig = {
      image = "ghcr.io/music-assistant/server:2.8.6";
      publishPorts = [ "127.0.0.1:8095:8095" ];
      networks = [
        "${network.ref}:ip=10.3.2.13"
      ];
      logDriver = "journald";
      environments = {
        TZ = "Europe/Stockholm";
      };
      volumes = [
        "/srv/appdata/home-auto/music-assistant:/data"
      ];
      addCapabilities = [ "NET_ADMIN" ];
    };
    unitConfig = {
      After = [ "home-auto-network.service" ];
      Requires = [ "home-auto-network.service" ];
    };
    serviceConfig = {
      Restart = "always";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/appdata/home-auto/music-assistant 0750 root root - -"
  ];

  environment.etc."alloy/music-assistant.alloy".text = ''
    loki.source.journal "music_assistant" {
      matches = "_SYSTEMD_UNIT=music-assistant.service"
      labels = {
        job = "music-assistant",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';

  services.nginx.virtualHosts."mass.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8095";
      proxyWebsockets = true;
    };
  };
}
