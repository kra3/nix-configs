{
  flake.nixosModules.services-home-automation-home-assistant =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.home-assistant = {
        containerConfig = {
          image = "ghcr.io/home-assistant/home-assistant:2026.11.3@sha256:24e541ddae5818bf8eb27898b9ba00d0c344a655aa5097e9e9bd4b19356be847";
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
