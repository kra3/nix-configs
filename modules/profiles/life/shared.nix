{
  # The key makes the module system drop repeat imports, so every life profile can import this.
  flake.nixosModules.profiles-life-shared =
    { flakeModules, ... }:
    {
      key = "profiles-life-shared";
      imports = [
        flakeModules.nixos.containers-life-network
        flakeModules.nixos.containers-life-storage
      ];

      users.groups.life = {
        gid = 2200;
      };
    };
}
