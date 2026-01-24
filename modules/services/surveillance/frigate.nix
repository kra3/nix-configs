{ config, lib, pkgs, ... }:
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
      detect = {
        enabled = true;
        width = 640;
        height = 480;
      };

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
        listen = [
          "fire_alarm"
          "explosion"
          "glass"
          "shatter"
          "scream"
          "yell"
          # "speech"
          "bark"
        ];
      };

      mqtt = {
        enabled = true;
        host = "10.0.50.8";
        port = 1883;
        user = "kothu";
        password = "@@MQTT_PASSWORD@@";
      };

      # required to trick frigate to enable restreaming support
      go2rtc = {
        streams = {
          ranger_duo_fxd = "rtsp://127.0.0.1:8554/ranger_duo_fxd";
          ranger_duo_fxd_sub = "rtsp://127.0.0.1:8554/ranger_duo_fxd_sub";
          ranger_duo_ptz = "rtsp://127.0.0.1:8554/ranger_duo_ptz";
          ranger_duo_ptz_sub = "rtsp://127.0.0.1:8554/ranger_duo_ptz_sub";
          ranger_uno = "rtsp://127.0.0.1:8554/ranger_uno";
          ranger_uno_sub = "rtsp://127.0.0.1:8554/ranger_uno_sub";
        };
      };

      cameras = {
        ranger_duo_fxd = {
          live = {
            streams = {
              Main = "ranger_duo_fxd";
              Sub = "ranger_duo_fxd_sub";
            };
          };
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
          live = {
            streams = {
              Main = "ranger_duo_ptz";
              Sub = "ranger_duo_ptz_sub";
            };
          };
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
          live = {
            streams = {
              Main = "ranger_uno";
              Sub = "ranger_uno_sub";
            };
          };
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

  services.nginx.virtualHosts."${config.services.frigate.hostname}".locations."/api/metrics" = {
    proxyPass = "http://frigate-api/metrics";
    recommendedProxySettings = true;
    extraConfig = ''
      auth_request off;
      access_log off;
      add_header Cache-Control "no-store";
    '';
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

          replacements = {
            "@@MQTT_PASSWORD@@": Path("/run/secrets/mqtt.users.kothu.password").read_text().strip(),
            "@@RANGER_DUO_PASSWORD@@": Path("/run/secrets/surveillance.go2rtc.ranger_duo.password").read_text().strip(),
            "@@RANGER_UNO_PASSWORD@@": Path("/run/secrets/surveillance.go2rtc.ranger_uno.password").read_text().strip(),
          }
          config_path = Path("/run/frigate/frigate.yml")
          content = config_path.read_text()
          for placeholder, secret in replacements.items():
            content = content.replace(placeholder, secret)
          config_path.write_text(content)
          config_path.chmod(0o640)
          PY
          chown frigate:frigate /run/frigate/frigate.yml
        '')
      ];
    };
  };

}
