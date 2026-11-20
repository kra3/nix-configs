{
  flake.nixosModules.profiles-home-automation-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-home-auto
        flakeModules.nixos.containers-home-auto-home-assistant-default
        flakeModules.nixos.containers-home-auto-otbr-default
        flakeModules.nixos.containers-home-auto-matter-server-default
      ];
    };
}
