{
  # The tmpfiles rule is `loginctl enable-linger` for kra3: PipeWire only runs in a logged-in session and this host has no graphical login.
  flake.nixosModules.services-media-sendspin =
    { pkgs, ... }:
    {
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

      networking.firewall.interfaces.wlan0.allowedTCPPorts = [ 8927 ];

      systemd.user.services.sendspin = {
        description = "Sendspin player";
        after = [ "pipewire-pulse.service" ];
        wants = [ "pipewire-pulse.service" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.sendspin-go}/bin/sendspin-go -daemon -name \"Kitchen Sendspin\"";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
}
