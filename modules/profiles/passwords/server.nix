{
  flake.nixosModules.profiles-passwords-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-life-shared
        flakeModules.nixos.containers-life-vaultwarden
      ];
    };
}
