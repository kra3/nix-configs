{
  flake.nixosModules.containers-home-auto-home-assistant-bluetooth = { pkgs, ... }:
  {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
