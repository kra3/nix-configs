{
  # Snapcast client, connecting to Music Assistant's bundled Snapcast server
  # (deployed on sutala, see modules/services/home-automation/music-assistant.nix
  # + modules/containers/home-auto/music-assistant/default.nix). MA's macvlan
  # interface gives that server a real LAN address, so no server-side firewall
  # or publish-port change is needed here -- just an outbound client connection.
  #
  # Output is either the onboard 3.5mm jack or a paired Bluetooth speaker, so
  # this runs on PipeWire (not a fixed ALSA device): WirePlumber's Bluetooth
  # policy makes a connected A2DP device the default sink automatically,
  # falling back to the analog jack when none is connected. snapclient talks
  # to PipeWire's pulse-compatible socket, so it always follows that default
  # rather than a hardcoded `hw:x,y` name. There is no NixOS
  # services.snapclient module, hence the manual systemd unit.
  #
  # PipeWire/WirePlumber normally only run in a logged-in user session; since
  # this host never has a graphical login, kra3's session is kept alive via
  # loginctl linger (the tmpfiles rule below is exactly what `loginctl
  # enable-linger` does), and snapclient itself is a per-user unit so it
  # shares that same session's pulse socket.
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
        ExecStart = "${pkgs.snapcast}/bin/snapclient -h ${config.vars.network.macvlanAddresses.musicAssistant} -p pulse";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
