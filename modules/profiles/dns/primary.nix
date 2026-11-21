{
  flake.nixosModules.profiles-dns-primary =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-dns-default
      ];
    };
}
