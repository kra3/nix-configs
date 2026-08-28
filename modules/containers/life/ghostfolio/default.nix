{
  flake.nixosModules.containers-life-ghostfolio-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.containers-life-ghostfolio-ghostfolio
      flakeModules.nixos.containers-life-ghostfolio-scraper
      flakeModules.nixos.containers-life-ghostfolio-backfill
    ];
  };
}
