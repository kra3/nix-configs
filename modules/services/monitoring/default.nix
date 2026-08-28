{
  flake.nixosModules.services-monitoring-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.services-monitoring-grafana
      flakeModules.nixos.services-monitoring-loki
      flakeModules.nixos.services-monitoring-prometheus
    ];
  };
}
