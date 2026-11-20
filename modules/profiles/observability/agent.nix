{
  flake.nixosModules.profiles-observability-agent =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-monitoring-alloy-host
      ];
    };
}
