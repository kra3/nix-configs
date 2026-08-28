{
  flake.nixosModules.containers-home-auto-otbr-default = { config, lib, pkgs, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.home-auto;
    macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
  in
  {
    virtualisation.quadlet.containers.otbr = {
      containerConfig = {
        image = "docker.io/denniswitt/homeassistant-otbr:4.2.2";
        publishPorts = [ "127.0.0.1:8081:8081" ];
        dns = [ "10.3.2.1" ];
        networks = [
          "${network.ref}:ip=10.3.2.11"
          "${macvlan.ref}:ip=192.168.1.34,mac=02:42:c0:a8:01:22"
        ];
        logDriver = "journald";
        volumes = [
          "/srv/appdata/home-auto/otbr:/data"
        ];
        devices = [
          "/dev/thread:/dev/ttyUSB0"
          "/dev/net/tun:/dev/net/tun"
        ];
        addCapabilities = [
          "NET_ADMIN"
          "NET_RAW"
        ];
        environments = {
          TZ = "Europe/Stockholm";
          DEVICE = "/dev/ttyUSB0";
          BAUDRATE = "460800";
          FLOW_CONTROL = "true";
          BACKBONE_IF = "eth1"; # macvlan (LAN) interface
          AUTOFLASH_FIRMWARE = "false";
          OTBR_LOG_LEVEL = "notice";
          FIREWALL = "true";
          NAT64 = "false";
        };
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
      extraAfter = [ "dev-thread.device" ];
      bindsTo = [ "dev-thread.device" ];
    };
  
    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/otbr 0750 root root - -"
    ];
  
    environment.etc."alloy/otbr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "otbr";
      hostName = config.networking.hostName;
    };
  };
}
