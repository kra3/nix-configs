{ lib, pkgs, ... }:
{
  services.frigate = {
    enable = true;
    hostname = "frigate.karunagath.in";
    settings = {
      mqtt = {
        enabled = true;
        host = "10.0.50.8";
        port = 1883;
        user = "kothu";
        password = "@@MQTT_PASSWORD@@";
      };
      cameras = {
        ranger_duo_fxd = {
          ffmpeg.inputs = [
            {
              path = "rtsp://127.0.0.1:8554/ranger_duo_fxd";
              roles = [
                "record"
              ];
            }
            {
              path = "rtsp://127.0.0.1:8554/ranger_duo_fxd_sub";
              roles = [
                "detect"
              ];
            }
          ];
        };
        ranger_duo_ptz = {
          ffmpeg.inputs = [
            {
              path = "rtsp://127.0.0.1:8554/ranger_duo_ptz";
              roles = [
                "record"
              ];
            }
            {
              path = "rtsp://127.0.0.1:8554/ranger_duo_ptz_sub";
              roles = [
                "detect"
              ];
            }
          ];
        };
        ranger_uno = {
          ffmpeg.inputs = [
            {
              path = "rtsp://127.0.0.1:8554/ranger_uno";
              roles = [
                "record"
              ];
            }
            {
              path = "rtsp://127.0.0.1:8554/ranger_uno_sub";
              roles = [
                "detect"
              ];
            }
          ];
        };
      };
      record.enabled = true;
    };
  };

  systemd.services.frigate = {
    serviceConfig = {
      PermissionsStartOnly = true;
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "frigate-apply-mqtt-secret" ''
          ${pkgs.python3}/bin/python - <<'PY'
          from pathlib import Path

          secret = Path("/run/secrets/mqtt.users.kothu.password").read_text().strip()
          config_path = Path("/run/frigate/frigate.yml")
          config_path.write_text(config_path.read_text().replace("@@MQTT_PASSWORD@@", secret))
          PY
        '')
      ];
    };
  };
}
