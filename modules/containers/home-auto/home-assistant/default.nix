{
  flake.nixosModules.containers-home-auto-home-assistant-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.containers-home-auto-home-assistant-network
      flakeModules.nixos.containers-home-auto-home-assistant-storage
      flakeModules.nixos.containers-home-auto-home-assistant-container
      flakeModules.nixos.containers-home-auto-home-assistant-bluetooth
    ];
  };
}
