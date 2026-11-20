{
  flake.nixosModules.services-media-servers-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.services-media-servers-jellyfin
      flakeModules.nixos.services-media-servers-navidrome
      # flakeModules.nixos.services-media-servers-snapserver
    ];
  };
}
