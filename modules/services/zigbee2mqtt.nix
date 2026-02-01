{ config, lib, ... }:
{
  services.zigbee2mqtt = {
    enable = true;
    dataDir = "/var/lib/zigbee2mqtt";
    settings = {
      homeassistant = {
        enabled = true;
      };
      mqtt = {
        server = "mqtt://localhost:1883";
      };
      serial = {
        adapter = "ember";
        baudrate = 115200;
        port = "/dev/zigbee";
        rtscts = false;
      };
      # Firmware tool: https://dongle.sonoff.tech/sonoff-dongle-flasher/
      frontend = {
        enabled = true;
        host = "0.0.0.0";
        port = 8080;
      };
    };
  };

  users.users.zigbee2mqtt = lib.mkIf config.services.zigbee2mqtt.enable {
    extraGroups = [
      "dialout"
    ];
  };

  systemd.services.zigbee2mqtt.serviceConfig.EnvironmentFile = "/run/secrets/zigbee2mqtt.env";
}
