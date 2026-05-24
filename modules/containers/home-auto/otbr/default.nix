{ config, pkgs, ... }:
let
  network = config.virtualisation.quadlet.networks.home-auto;
  macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
in
{
  virtualisation.quadlet.containers.otbr = {
    containerConfig = {
      image = "docker.io/denniswitt/homeassistant-otbr:3.0.5";
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
    unitConfig = {
      After = [
        "home-auto-network.service"
        "home-auto-macvlan-network.service"
        "dev-thread.device"
      ];
      Requires = [
        "home-auto-network.service"
        "home-auto-macvlan-network.service"
      ];
      BindsTo = [ "dev-thread.device" ];
    };
    serviceConfig = {
      Restart = "always";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/appdata/home-auto/otbr 0750 root root - -"
  ];

  environment.etc."alloy/otbr.alloy".text = ''
    loki.source.journal "otbr" {
      matches = "_SYSTEMD_UNIT=otbr.service"
      labels = {
        job = "otbr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';
}
