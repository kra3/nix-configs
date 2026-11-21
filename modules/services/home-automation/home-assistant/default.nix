{
  flake.nixosModules.services-home-automation-home-assistant =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.home-assistant = {
        containerConfig = {
          image = "ghcr.io/home-assistant/home-assistant:2026.11.2@sha256:493a07e8f6530fc640223f4a0a5248f20a61ca2f718bb1d31efbf08a2c5ea28f";
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
