{
  flake.nixosModules.containers-home-auto-matter-server-default = { config, lib, pkgs, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.home-auto;
    macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
  in
  {
    virtualisation.quadlet.containers.matter-server = {
      containerConfig = {
        image = "ghcr.io/home-assistant-libs/python-matter-server:8.1.0";
        publishPorts = [ "127.0.0.1:5580:5580" ];
        dns = [ "10.3.2.1" ];
        networks = [
          "${network.ref}:ip=10.3.2.12"
          "${macvlan.ref}:ip=192.168.1.35,mac=02:42:c0:a8:01:23"
        ];
        logDriver = "journald";
        volumes = [
          "/srv/appdata/home-auto/matter-server:/data"
        ];
        addCapabilities = [ "NET_ADMIN" ];
        environments = {
          TZ = "Europe/Stockholm";
        };
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
      extraAfter = [ "otbr.service" ];
    };
  
    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/matter-server 0750 root root - -"
    ];
  
    environment.etc."alloy/matter-server.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "matter-server";
      id = "matter_server";
      hostName = config.networking.hostName;
    };
  };
}
