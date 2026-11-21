{
  flake.nixosModules.profiles-surveillance-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-surveillance-proxy
      ];
    };
}
