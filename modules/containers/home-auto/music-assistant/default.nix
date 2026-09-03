{
  flake.nixosModules.containers-home-auto-music-assistant-default = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.home-auto;
    macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
  in
  {
    imports = [ flakeModules.nixos.services-home-automation-music-assistant ];

    virtualisation.quadlet.containers.music-assistant = {
      containerConfig = {
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
        volumes = [
          "/srv/appdata/home-auto/music-assistant:/data"
        ];
        addCapabilities = [ "NET_ADMIN" ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "1408Mi";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
    };

    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/music-assistant 0750 root root - -"
    ];

    services.nginx.virtualHosts."ma.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:8095";
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
      extraConfig = flakeLib.nginx.mkAllowBlock config.vars.network.nginxAllowCidrs;
      locations."/" = {
        proxyPass = "http://10.3.2.13:1705";
        proxyWebsockets = true;
      };
    };

    networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [ 1705 ];
  };
}
