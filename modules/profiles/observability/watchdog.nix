{
  flake.nixosModules.profiles-observability-watchdog =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-monitoring-sutala-watchdog
      ];
    };
}
