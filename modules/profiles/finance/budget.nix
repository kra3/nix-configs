{
  flake.nixosModules.profiles-finance-budget =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-life-shared
        flakeModules.nixos.containers-life-actualbudget
      ];
    };
}
