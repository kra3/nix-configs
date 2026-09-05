{
  flake.nixosModules.containers-home-auto-home-assistant-bluetooth = { pkgs, ... }:
  {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # bluetoothd segfaults under yalexs_ble's BLE retry storms; widen the crash-loop budget so a burst of crashes can't wedge the unit into a permanent failed state, and restart it directly rather than relying solely on D-Bus activation.
    systemd.services.bluetooth = {
      serviceConfig.Restart = "on-failure";
      startLimitIntervalSec = 300;
      startLimitBurst = 10;
    };
  };
}
