{ lib, pkgs, ... }:
{
  environment.sessionVariables = {
    LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
    LIBVA_DRIVER_NAME = "iHD";
  };
  environment.systemPackages = [
    pkgs.intel-compute-runtime
    pkgs.intel-media-driver
    pkgs.intel-vaapi-driver
    pkgs.vpl-gpu-rt
  ];
  users.groups.render = { };
  users.groups.video = { };
  users.users.frigate.extraGroups = [
    "render"
    "video"
  ];

  services.frigate = {
    enable = true;
    hostname = "nvr.karunagath.in";
    vaapiDriver = "iHD";
    checkConfig = false;
    settings = {
      detectors = {
        cpu = {
          type = "cpu";
        };
      };

      ffmpeg = {
        path = pkgs.ffmpeg-full;
        input_args = "preset-rtsp-restream";
        hwaccel_args = "preset-vaapi";
        output_args = {
          record = "preset-record-generic-audio-copy";
        };
      };

      motion = {
        enabled = true;
      };

      audio = {
        enabled = true;
      };

      mqtt = {
        enabled = true;
        host = "10.0.50.8";
        port = 1883;
        user = "kothu";
        password = "@@MQTT_PASSWORD@@";
      };

      cameras = {
        ranger_duo_fxd = {
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/ranger_duo_fxd";
                roles = [
                  "record"
                ];
              }
              {
                path = "rtsp://127.0.0.1:8554/ranger_duo_fxd_sub";
                roles = [
                  "audio"
                  "detect"
                ];
              }
            ];
          };
        };
        ranger_duo_ptz = {
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/ranger_duo_ptz";
                roles = [
                  "record"
                ];
              }
              {
                path = "rtsp://127.0.0.1:8554/ranger_duo_ptz_sub";
                roles = [
                  "audio"
                  "detect"
                ];
              }
            ];
          };
        };
        ranger_uno = {
          ffmpeg = {
            inputs = [
              {
                path = "rtsp://127.0.0.1:8554/ranger_uno";
                roles = [
                  "record"
                ];
              }
              {
                path = "rtsp://127.0.0.1:8554/ranger_uno_sub";
                roles = [
                  "audio"
                  "detect"
                ];
              }
            ];
          };
        };
      };
      
      record = {
        enabled = true;
        retain = {
          days = 0;
          mode = "motion";
        };
      };
    };
  };

  systemd.services.frigate = {
    environment = {
      LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
      LIBVA_DRIVER_NAME = "iHD";
    };
    serviceConfig = {
      PermissionsStartOnly = true;
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "frigate-apply-mqtt-secret" ''
          ${pkgs.python3}/bin/python - <<'PY'
          from pathlib import Path

          secret = Path("/run/secrets/mqtt.users.kothu.password").read_text().strip()
          config_path = Path("/run/frigate/frigate.yml")
          config_path.write_text(config_path.read_text().replace("@@MQTT_PASSWORD@@", secret))
          config_path.chmod(0o640)
          PY
          chown frigate:frigate /run/frigate/frigate.yml
        '')
      ];
    };
  };

}
