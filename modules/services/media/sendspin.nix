{
  # The tmpfiles rule is `loginctl enable-linger` for kra3: PipeWire only runs in a logged-in session and this host has no graphical login.
  flake.nixosModules.services-media-sendspin =
    { config, pkgs, ... }:
    let
      avahiCompat = pkgs.avahi.override { withLibdnssdCompat = true; };

      # The release binary: building from source fetches sendspin-cpp and its dependencies at configure time.
      sendspin-cli = pkgs.stdenv.mkDerivation rec {
        pname = "sendspin-cli";
        version = "0.3.0";
        src = pkgs.fetchurl {
          url = "https://github.com/Sendspin/sendspin-cpp-cli/releases/download/v${version}/sendspin-cli-${version}-linux-arm64.tar.gz";
          hash = "sha256-SQNbJ50UDQmcibSWg3N5vZvlDss6if5iorYMj1JD4mQ=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [
          pkgs.alsa-lib
          pkgs.portaudio
          pkgs.libpulseaudio
          pkgs.pipewire
          avahiCompat
          pkgs.stdenv.cc.cc.lib
        ];
        installPhase = "install -Dm755 usr/local/bin/sendspin-cli $out/bin/sendspin-cli";
        meta.platforms = [ "aarch64-linux" ];
      };
    in
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
          ExecStart = "${sendspin-cli}/bin/sendspin-cli -n \"Kitchen Eneby\" -s ${config.vars.network.macvlanAddresses.musicAssistant}:8927 -o pipewire --allow-unpaired";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
}
