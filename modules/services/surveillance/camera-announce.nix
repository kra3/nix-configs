{
  flake.nixosModules.services-surveillance-camera-announce =
    { config, pkgs, ... }:
    let
      announce = pkgs.writers.writePython3 "camera-announce" {
        doCheck = false;
      } (builtins.readFile ./camera-announce.py);
    in
    {
      sops.templates."camera-announce.env" = {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          CAMERA_USER=${config.sops.placeholder."surveillance.go2rtc.ranger_uno.user"}
          CAMERA_PASSWORD=${config.sops.placeholder."surveillance.go2rtc.ranger_uno.password"}
        '';
        restartUnits = [ "camera-announce.service" ];
      };

      systemd.services.camera-announce = {
        description = "Speak through the hallway camera speaker (Piper TTS to Imou talk)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "home-auto-network.service" ];
        after = [ "home-auto-network.service" ];
        path = [ pkgs.ffmpeg-headless ];
        environment = {
          LISTEN = "10.3.2.1:8098";
          PIPER_HOST = "10.3.2.15";
          CAMERA_HOST = "192.168.1.22";
          TALK_TRACK = "64";
          PLAY_URL_PREFIX = "http://10.3.2.10:8123/local/";
        };
        serviceConfig = {
          ExecStart = announce;
          EnvironmentFile = config.sops.templates."camera-announce.env".path;
          DynamicUser = true;
          Restart = "always";
          RestartSec = 10;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };

      networking.firewall.interfaces.br-home-auto.allowedTCPPorts = [ 8098 ];
    };
}
