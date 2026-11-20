{
  flake.nixosModules.profiles-fitness-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-fitness-default
      ];
    };
}
