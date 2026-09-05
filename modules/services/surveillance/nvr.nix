{
  flake.nixosModules.services-surveillance-nvr =
  { config, lib, pkgs, containerLocalAddress, ... }:
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

    streamWithCreds = prefix: cam: stream:
      lib.replaceStrings
        [ "{USER}" "{PASS}" ]
        [ "{${prefix}${cam.userEnv}}" "{${prefix}${cam.passwordEnv}}" ]
        stream;

    streamWithCredsEnv = cam: stream:
      lib.replaceStrings
        [ "{USER}" "{PASS}" ]
        [ "\${${cam.userEnv}}" "\${${cam.passwordEnv}}" ]
        stream;

    go2rtcStreamsFor = prefix:
      lib.foldlAttrs (acc: name: cam: acc // {
        "${name}" =
          if prefix == ""
          then streamWithCredsEnv cam cam.main
          else streamWithCreds prefix cam cam.main;
        "${name}_sub" =
          if prefix == ""
          then streamWithCredsEnv cam cam.sub
          else streamWithCreds prefix cam cam.sub;
      }) { } cameras;

    # Coordinates are normalized (0-1) polygons drawn in the Frigate UI
    # (Settings > Masks / Zones) to exclude windows/curtains and the
    # camera timestamp overlay from motion detection.
    motionMasks = {
      ranger_duo_fxd = [
        "0,0.545,0.117,0.618,0.123,1,0.004,0.992"
        "0.633,0.012,0.99,0.012,0.99,0.089,0.633,0.089"
      ];
      ranger_duo_ptz = [
        "0.791,0.22,0.967,0.245,0.954,0.545,0.787,0.516"
        "0.641,0.042,0.642,0.087,0.996,0.087,0.988,0.029"
      ];
      ranger_uno = "0.665,0.012,0.99,0.012,0.99,0.095,0.665,0.095";
    };

    frigateCameras = lib.mapAttrs (name: cam: {
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
    } // lib.optionalAttrs (cam.onvif != null) {
      onvif = {
        host = cam.onvif.host;
        port = cam.onvif.port;
        user = "{FRIGATE_${cam.userEnv}}";
        password = "{FRIGATE_${cam.passwordEnv}}";
        autotracking = {
          enabled = false;
        };
      };
    } // lib.optionalAttrs (motionMasks ? ${name}) {
      motion.mask = motionMasks.${name};
    }) cameras;

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

    # to allow peometheus to parse metrics. without it is failing 401.
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
        serviceConfig.EnvironmentFile = "/run/secrets/surveillance-nvr-frigate.env";
      };

      go2rtc = {
        serviceConfig = {
          EnvironmentFile = "/run/secrets/surveillance-nvr-go2rtc.env";
          StateDirectory = lib.mkForce [ ];
        };
      };

      # ranger_duo_fxd's motion sensor has been seen going silently stale
      # (camera/go2rtc stream freezes but frigate itself stays healthy, so
      # nothing errors) with only a full `systemctl restart frigate` clearing
      # it. Neither Frigate nor go2rtc expose a narrower per-camera/stream
      # restart API (upstream: blakeblackshear/frigate#15725, closed
      # not-planned; AlexxIT/go2rtc#1136, open) -- a full restart is the only
      # available lever, so this watches just that one camera and applies it
      # automatically instead of waiting on the hourly HA notification.
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
      serviceConfig.Type = "oneshot";
      path = [ pkgs.coreutils pkgs.systemd ];
      script = ''
        stamp=/run/frigate-motion-watchdog/ranger_duo_fxd.stamp
        if [ ! -e "$stamp" ]; then
          echo "no stamp yet, skipping"
          exit 0
        fi
        age=$(( $(date +%s) - $(stat -c %Y "$stamp") ))
        if [ "$age" -gt $(( 4 * 3600 )) ]; then
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
