{
  flake.nixosModules.containers-life-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.containers-life-network
      flakeModules.nixos.containers-life-storage
      flakeModules.nixos.containers-life-actualbudget
      flakeModules.nixos.containers-life-ghostfolio-default
    ];

    users.groups.life = {
      gid = 2200;
    };
  };
}
