{
  flake.nixosModules.services-home-automation-otbr =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.otbr = {
        containerConfig = {
          image = "docker.io/denniswitt/homeassistant-otbr:4.2.3";
          publishPorts = [ "127.0.0.1:8081:8081" ];
          logDriver = "journald";
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
      };

      environment.etc."alloy/otbr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "otbr";
        hostName = config.networking.hostName;
      };
    };
}
