{
  # The tmpfiles rule is `loginctl enable-linger` for kra3: PipeWire only runs in a logged-in session and this host has no graphical login.
  flake.nixosModules.services-media-pi-audio = {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    systemd.tmpfiles.rules = [
      "f /var/lib/systemd/linger/kra3 0644 root root -"
    ];
  };
}
