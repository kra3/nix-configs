{
  flake.nixosModules.profiles-dns-secondary =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-dns-rpi-secondary
      ];
    };
}
