{
  flake.nixosModules.services-media-sendspin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.sendspin-player;

      avahiCompat = pkgs.avahi.override { withLibdnssdCompat = true; };

      release = {
        aarch64-linux = {
          arch = "arm64";
          hash = "sha256-SQNbJ50UDQmcibSWg3N5vZvlDss6if5iorYMj1JD4mQ=";
        };
        x86_64-linux = {
          arch = "x86_64";
          hash = "sha256-FeUjZKvjbIKbBNif98M0f/vVxZ0bmJYFvYBRx/QCgS4=";
        };
      };

      # The release binary: building from source fetches sendspin-cpp and its dependencies at configure time.
      sendspin-cli = pkgs.stdenv.mkDerivation rec {
        pname = "sendspin-cli";
        version = "0.3.0";
        src = pkgs.fetchurl {
          url = "https://github.com/Sendspin/sendspin-cpp-cli/releases/download/v${version}/sendspin-cli-${version}-linux-${
            release.${pkgs.stdenv.hostPlatform.system}.arch
          }.tar.gz";
          inherit (release.${pkgs.stdenv.hostPlatform.system}) hash;
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
        meta.platforms = builtins.attrNames release;
      };
    in
    {
      options.services.sendspin-player = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Player name shown in Music Assistant";
        };
        server = lib.mkOption {
          type = lib.types.str;
          default = config.vars.network.macvlanAddresses.musicAssistant;
          description = "Music Assistant address";
        };
        output = lib.mkOption {
          type = lib.types.str;
          default = "pipewire";
          description = "sendspin-cli -o value";
        };
        pipewireNode = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "PipeWire sink the player is pinned to; the default sink when null";
        };
      };

      config.systemd.user.services.sendspin = {
        description = "Sendspin player";
        after = [ "pipewire-pulse.service" ];
        wants = [ "pipewire-pulse.service" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${sendspin-cli}/bin/sendspin-cli -n \"${cfg.name}\" -s ${cfg.server}:8927 -o ${cfg.output}";
          Environment = lib.optional (cfg.pipewireNode != null) "PIPEWIRE_NODE=${cfg.pipewireNode}";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
}
