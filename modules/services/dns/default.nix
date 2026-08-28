{
  flake.nixosModules.services-dns-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.services-dns-adguard
      flakeModules.nixos.services-dns-unbound
    ];
  };
}
