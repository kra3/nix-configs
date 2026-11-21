{
  flake.nixosModules.profiles-observability-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-monitoring
        # Grafana's "Home Assistant" datasource reads the hass db as grafana_ro.
        flakeModules.nixos.services-postgres
      ];
    };
}
