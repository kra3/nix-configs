{
  flake.nixosModules.services-media-sendspin =
    {
      inputs,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.sendspin-player;

      sendspin-cli = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.sendspin-cli;
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
          description = "sendspin-cli -o value; pulse:<sink> pins a sink";
        };
      };

      config.systemd.user.services.sendspin = {
        description = "Sendspin player";
        after = [ "pipewire-pulse.service" ];
        wants = [ "pipewire-pulse.service" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          ExecStart = "${sendspin-cli}/bin/sendspin-cli -n \"${cfg.name}\" -s ${cfg.server}:8927 -o ${cfg.output}";
          Restart = "always";
          RestartSec = "5s";
        };
      };
    };
}
