{
  flake.nixosModules.profiles-observability-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-monitoring
      ];
    };
}
