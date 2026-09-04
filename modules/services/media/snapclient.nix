{
  # Snapcast client for Music Assistant's bundled server (sutala, via its macvlan address) -- outbound-only, no server-side change needed.
  # Runs on PipeWire/WirePlumber (not a fixed ALSA device) so it follows whichever output (jack or a paired A2DP speaker) WirePlumber picks as default sink; no NixOS services.snapclient module exists, hence the manual unit.
  # The tmpfiles rule below is `loginctl enable-linger` for kra3, since PipeWire only runs in a logged-in session and this host has no graphical login.
  flake.nixosModules.services-media-snapclient =
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

      systemd.user.services.snapclient = {
        description = "Snapcast client";
        after = [ "pipewire-pulse.service" ];
        wants = [ "pipewire-pulse.service" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.snapcast}/bin/snapclient -h ${config.vars.network.macvlanAddresses.musicAssistant} --player pulse";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
}
