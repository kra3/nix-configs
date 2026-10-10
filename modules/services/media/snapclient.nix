{
  # Snapcast client for Music Assistant's bundled server (sutala, via its macvlan address) -- outbound-only, no server-side change needed.
  # PipeWire and linger come from services-media-sendspin; no NixOS services.snapclient module exists, hence the manual unit.
  flake.nixosModules.services-media-snapclient =
    { config, pkgs, ... }:
    {
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
