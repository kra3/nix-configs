{
  flake.nixosModules.containers-life-ghostfolio-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.containers-life-ghostfolio-ghostfolio
      flakeModules.nixos.services-finance-ghostfolio-scraper
      flakeModules.nixos.services-finance-ghostfolio-backfill
    ];
  };
}
