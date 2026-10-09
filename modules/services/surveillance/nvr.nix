{
  flake.nixosModules.services-surveillance-nvr =
    {
      config,
      lib,
      pkgs,
      containerLocalAddress,
      ...
    }:
    let
      cameras = {
        ranger_duo_fxd = {
          userEnv = "RANGER_DUO_USER";
          passwordEnv = "RANGER_DUO_PASSWORD";
          main = "rtsp://{USER}:{PASS}@192.168.1.21:554/cam/realmonitor?channel=2&subtype=0";
          sub = "rtsp://{USER}:{PASS}@192.168.1.21:554/cam/realmonitor?channel=2&subtype=1";
          onvif = null;
        };
        ranger_duo_ptz = {
          userEnv = "RANGER_DUO_USER";
          passwordEnv = "RANGER_DUO_PASSWORD";
          main = "rtsp://{USER}:{PASS}@192.168.1.21:554/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif";
          sub = "rtsp://{USER}:{PASS}@192.168.1.21:554/cam/realmonitor?channel=1&subtype=1#backchannel=0";
          onvif = {
            host = "192.168.1.21";
            port = 80;
          };
        };
        ranger_uno = {
          userEnv = "RANGER_UNO_USER";
          passwordEnv = "RANGER_UNO_PASSWORD";
          main = "rtsp://{USER}:{PASS}@192.168.1.22:554/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif";
          sub = "rtsp://{USER}:{PASS}@192.168.1.22:554/cam/realmonitor?channel=1&subtype=1#backchannel=0";
          onvif = {
            host = "192.168.1.22";
            port = 80;
          };
        };
      };

      streamWithCreds =
        prefix: cam: stream:
        lib.replaceStrings
          [ "{USER}" "{PASS}" ]
          [ "{${prefix}${cam.userEnv}}" "{${prefix}${cam.passwordEnv}}" ]
          stream;

      streamWithCredsEnv =
        cam: stream:
        lib.replaceStrings [ "{USER}" "{PASS}" ] [ "\${${cam.userEnv}}" "\${${cam.passwordEnv}}" ] stream;

      go2rtcStreamsFor =
        prefix:
        lib.foldlAttrs (
          acc: name: cam:
          acc
          // {
            "${name}" =
              if prefix == "" then streamWithCredsEnv cam cam.main else streamWithCreds prefix cam cam.main;
            "${name}_sub" =
              if prefix == "" then streamWithCredsEnv cam cam.sub else streamWithCreds prefix cam cam.sub;
          }
        ) { } cameras;

      # Coordinates are normalized (0-1) polygons drawn in the Frigate UI
      # (Settings > Masks / Zones) to exclude windows/curtains and the
      # camera timestamp overlay from motion detection.
      # UI edits only live in /run/frigate/frigate.yml and are lost on restart, so port them here.
      motionMasks = {
        ranger_duo_fxd = [
          "0,0.545,0.053,0.519,0.058,1,0.004,0.992"
          "0.633,0.012,0.99,0.012,0.99,0.089,0.633,0.089"
        ];
        ranger_duo_ptz = [
          "0.791,0.22,0.967,0.245,0.954,0.545,0.787,0.516"
          "0.641,0.042,0.642,0.087,0.996,0.087,0.988,0.029"
        ];
        ranger_uno = "0.665,0.012,0.99,0.012,0.99,0.095,0.665,0.095";
      };

      zones = {
        ranger_duo_fxd.living_room = {
          coordinates = "0.051,0.482,0.53,0.567,0.532,0.996,0.059,0.998";
          loitering_time = 0;
        };
        ranger_duo_ptz.dining_room = {
          coordinates = "0.384,0.441,0.39,0.652,0.006,0.849,0.001,0.996,0.761,0.99,0.826,0.828,0.848,0.747,0.69,0.71,0.662,0.7,0.658,0.482";
          loitering_time = 0;
        };
        ranger_uno.hallway = {
          coordinates = "0.3,0.213,0.558,0.209,0.572,0.884,0.72,0.88,0.732,0.534,0.72,0.358,0.994,0.302,0.996,0.698,0.72,0.973,0.03,0.99,0.022,0.211";
          loitering_time = 0;
        };
      };

      noContrastBoost = [
        "ranger_duo_fxd"
        "ranger_duo_ptz"
      ];

      reviewRequiredZones = {
        ranger_duo_fxd = "living_room";
      };

      frigateCameras = lib.mapAttrs (
        name: cam:
        {
          live.streams = {
            Main = name;
            Sub = "${name}_sub";
          };
          ffmpeg.inputs = [
            {
              path = "rtsp://127.0.0.1:8554/${name}";
              hwaccel_args = "preset-intel-qsv-h265";
              roles = [
                "record"
              ];
            }
            {
              path = "rtsp://127.0.0.1:8554/${name}_sub";
              hwaccel_args = "preset-intel-qsv-h264";
              roles = [
                "audio"
                "detect"
              ];
            }
          ];
        }
        // lib.optionalAttrs (cam.onvif != null) {
          onvif = {
            host = cam.onvif.host;
            port = cam.onvif.port;
            user = "{FRIGATE_${cam.userEnv}}";
            password = "{FRIGATE_${cam.passwordEnv}}";
            autotracking = {
              enabled = false;
            };
          };
        }
        // lib.optionalAttrs (motionMasks ? ${name} || builtins.elem name noContrastBoost) {
          motion =
            lib.optionalAttrs (motionMasks ? ${name}) { mask = motionMasks.${name}; }
            // lib.optionalAttrs (builtins.elem name noContrastBoost) { improve_contrast = false; };
        }
        // lib.optionalAttrs (zones ? ${name}) {
          zones = zones.${name};
        }
        // lib.optionalAttrs (reviewRequiredZones ? ${name}) {
          review = {
            alerts.required_zones = reviewRequiredZones.${name};
            detections.required_zones = reviewRequiredZones.${name};
          };
        }
      ) cameras;

    in
    {
      users.groups.frigate = {
        gid = 2100;
      };
      users.groups.render = { };
      users.groups.video = { };
      users.users.frigate.extraGroups = [
        "render"
        "video"
      ];

      services.frigate = {
        enable = true;
        hostname = "localhost";
        vaapiDriver = "iHD";
        checkConfig = false;
        settings = {
          audio = {
            enabled = true;
            listen = [
              "fire_alarm"
              "glass"
              "shatter"
              "scream"
              #"explosion"
              #"yell"
              # "speech"
              #"bark"
            ];
          };

          birdseye = {
            enabled = true;
            restream = false;
          };

          cameras = frigateCameras;

          detect = {
            enabled = true;
            width = 640;
            height = 480;
            fps = 4;
          };

          objects = {
            track = [
              "person"
              "dog"
              "cat"
            ];
          };

          detectors = {
            openvino = {
              type = "openvino";
              device = "GPU";
            };
          };

          ffmpeg = {
            path = pkgs.ffmpeg-full;
            input_args = "preset-rtsp-restream";
            output_args = {
              record = "preset-record-generic-audio-copy";
            };
          };

          go2rtc.streams = go2rtcStreamsFor "FRIGATE_";

          model = {
            width = 300;
            height = 300;
            input_tensor = "nhwc";
            input_pixel_format = "bgr";
            path = "/var/lib/frigate/models/ssdlite_mobilenet_v2/ssdlite_mobilenet_v2.xml";
            labelmap_path = "${config.services.frigate.package}/share/frigate/coco_91cl_bkgr.txt";
          };

          motion = {
            enabled = true;
            threshold = 35;
            contour_area = 40;
            lightning_threshold = 0.5;
          };

          mqtt = {
            enabled = true;
            host = "localhost";
            port = 1883;
            user = "{FRIGATE_MQTT_USER}";
            password = "{FRIGATE_MQTT_PASSWORD}";
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

      # auth_request off only skips Authelia; Frigate's own proxy-auth still needs a Remote-User header or it 401s.
      services.nginx.virtualHosts."${config.services.frigate.hostname}" = {
        serverAliases = [
          containerLocalAddress
          "localhost"
        ];
        locations."/api/metrics" = {
          proxyPass = "http://frigate-api/metrics";
          recommendedProxySettings = true;
          extraConfig = ''
            auth_request off;
            proxy_set_header Remote-User "prometheus";
            access_log off;
            add_header Cache-Control "no-store";
          '';
        };
      };

      services.go2rtc = {
        enable = true;
        settings = {
          ffmpeg = {
            bin = "${pkgs.ffmpeg-full}/bin/ffmpeg";
          };
          api.listen = "0.0.0.0:1984";
          api.origin = "*";
          rtsp.listen = "127.0.0.1:8554";
          webrtc = {
            listen = ":8555";
            candidates = [
              "192.168.1.10:8555"
            ];
          };
          streams = go2rtcStreamsFor "";
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/cache/nginx 0750 nginx nginx - -"
        "d /var/cache/nginx/frigate 0750 nginx nginx - -"
        "d /run/frigate-motion-watchdog 0750 root root - -"
      ];

      systemd.services = {
        frigate = {
          environment = {
            LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
          };
          serviceConfig = {
            EnvironmentFile = "/run/secrets/surveillance-nvr-frigate.env";
            # frigate ignores SIGTERM, so it was stalling every switch for the full 90s default.
            TimeoutStopSec = 20;
          };
        };

        go2rtc = {
          serviceConfig = {
            EnvironmentFile = "/run/secrets/surveillance-nvr-go2rtc.env";
            StateDirectory = lib.mkForce [ ];
          };
        };

        # No narrower per-camera/stream restart exists upstream (frigate#15725 closed not-planned, go2rtc#1136 open), so a full restart is the only remediation.
        frigate-motion-watch = {
          description = "Track ranger_duo_fxd motion-state changes for the stale-motion watchdog";
          wantedBy = [ "multi-user.target" ];
          after = [ "mosquitto.service" ];
          wants = [ "mosquitto.service" ];
          serviceConfig = {
            EnvironmentFile = "/run/secrets/surveillance-nvr-frigate.env";
            ExecStart = pkgs.writeShellScript "frigate-motion-watch" ''
              set -eu
              touch /run/frigate-motion-watchdog/ranger_duo_fxd.stamp
              ${pkgs.mosquitto}/bin/mosquitto_sub -h localhost -p 1883 \
                -u "$FRIGATE_MQTT_USER" -P "$FRIGATE_MQTT_PASSWORD" \
                -t frigate/ranger_duo_fxd/motion |
              while IFS= read -r _; do
                touch /run/frigate-motion-watchdog/ranger_duo_fxd.stamp
              done
            '';
            Restart = "always";
            RestartSec = 10;
          };
        };
      };

      systemd.services.frigate-restart-on-stale-motion = {
        description = "Restart frigate if ranger_duo_fxd's motion sensor has gone stale";
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = "/run/secrets/surveillance-nvr-frigate.env";
        };
        path = [
          pkgs.coreutils
          pkgs.systemd
          pkgs.mosquitto
        ];
        script = ''
          stamp=/run/frigate-motion-watchdog/ranger_duo_fxd.stamp
          if [ ! -e "$stamp" ]; then
            echo "no stamp yet, skipping"
            exit 0
          fi
          age=$(( $(date +%s) - $(stat -c %Y "$stamp") ))
          if [ "$age" -gt $(( 4 * 3600 )) ]; then
            # A restart reports motion on startup, which trips the alarm; an empty house is also why motion went quiet.
            alarm=$(mosquitto_sub -h localhost -p 1883 -u "$FRIGATE_MQTT_USER" -P "$FRIGATE_MQTT_PASSWORD" \
              -t alarmo/state -C 1 -W 5 2>/dev/null || true)
            if [ -n "$alarm" ] && [ "$alarm" != disarmed ]; then
              echo "ranger_duo_fxd motion stale for ''${age}s, but alarm is $alarm, skipping restart"
              exit 0
            fi
            echo "ranger_duo_fxd motion stale for ''${age}s, restarting frigate"
            systemctl restart frigate.service
            touch "$stamp"
          fi
        '';
      };

      systemd.timers.frigate-restart-on-stale-motion = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30min";
          OnUnitActiveSec = "15min";
        };
      };
    };
}
