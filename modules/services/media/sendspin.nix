{
  # The tmpfiles rule is `loginctl enable-linger` for kra3: PipeWire only runs in a logged-in session and this host has no graphical login.
  flake.nixosModules.services-media-sendspin =
    { config, pkgs, ... }:
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

      systemd.user.services.sendspin = {
        description = "Sendspin player";
        after = [ "pipewire-pulse.service" ];
        wants = [ "pipewire-pulse.service" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          # The player dials out; mDNS found no server, so point it at Music Assistant directly.
          ExecStart = "${pkgs.sendspin-go}/bin/sendspin-go -daemon -name \"Kitchen Eneby\" -server ${config.vars.network.macvlanAddresses.musicAssistant}:8927";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
}
