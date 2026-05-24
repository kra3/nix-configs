{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  network = config.virtualisation.quadlet.networks.home-auto;
  macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
in
{
  virtualisation.quadlet.containers.music-assistant = {
    containerConfig = {
      image = "ghcr.io/music-assistant/server:2.8.8";
      publishPorts = [
        "127.0.0.1:8095:8095"
      ];
      networks = [
        "${network.ref}:ip=10.3.2.13"
        "${macvlan.ref}:ip=192.168.1.36,mac=02:42:c0:a8:01:24"
      ];
      # Bypasses macvlan isolation by forcing host domains to the bridge gateway
      addHosts = [
        "ha.${config.vars.acme.domain}:10.3.2.1"
        "navidrome.${config.vars.acme.domain}:10.3.2.1"
        "audiobookshelf.${config.vars.acme.domain}:10.3.2.1"
        "ht:192.168.1.75"
        "home-theater:192.168.1.75"
      ];
      dns = [ "10.3.2.1" ];
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

  services.nginx.virtualHosts."ma.${config.vars.acme.domain}" = {
    useACMEHost = config.vars.acme.domain;
    forceSSL = true;
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8095";
      proxyWebsockets = true;
    };
  };

  # Snapcast JSON-RPC WebSocket on 1705 (ws/wss)
  services.nginx.virtualHosts."ma-snapcast" = {
    serverName = "ma.${config.vars.acme.domain}";
    useACMEHost = config.vars.acme.domain;
    onlySSL = true;
    listen = [
      {
        addr = "0.0.0.0";
        port = 1705;
        ssl = true;
      }
    ];
    extraConfig = allowBlock;
    locations."/" = {
      proxyPass = "http://10.3.2.13:1705";
      proxyWebsockets = true;
    };
  };

  networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [ 1705 ];
}
