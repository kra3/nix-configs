{
  flake.nixosModules.services-home-automation-home-assistant = { config, flakeLib, ... }:
  {
    virtualisation.quadlet.containers.home-assistant = {
      containerConfig = {
        image = "ghcr.io/home-assistant/home-assistant:2026.8.2";
        publishPorts = [ "127.0.0.1:8123:8123" ];
        logDriver = "journald";
        environments = {
          TZ = "Europe/Stockholm";
          DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";
        };
      };
    };

    environment.etc."alloy/home-assistant.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "home-assistant";
      id = "home_assistant";
      hostName = config.networking.hostName;
    };
  };
}
