{
  flake.nixosModules.services-media-players-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.services-media-players-jellyfin
      flakeModules.nixos.services-media-players-navidrome
      # ./snapserver.nix
    ];
  };
}
