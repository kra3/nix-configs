{
  flake.nixosModules.containers-home-auto-home-assistant-bluetooth = { pkgs, ... }:
  {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # bluetoothd segfaults under yalexs_ble's BLE retry storms; widen the crash budget so a burst can't wedge it failed.
    systemd.services.bluetooth = {
      serviceConfig.Restart = "on-failure";
      startLimitIntervalSec = 300;
      startLimitBurst = 10;
    };
  };
}
