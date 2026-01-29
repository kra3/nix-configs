{ config, lib, pkgs, ... }:
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
  }) cameras;

in
{
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
          "explosion"
          "glass"
          "shatter"
          "scream"
          #"yell"
          # "speech"
          #"bark"
        ];
      };

      birdseye = {
        enabled = true;
        restream = true;
      };

      cameras = frigateCameras;
      
      detect = {
        enabled = true;
        width = 640;
        height = 480;
        fps = 5;
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

  services.go2rtc = {
    enable = true;
    settings = {
      ffmpeg = {
        bin = "${pkgs.ffmpeg-full}/bin/ffmpeg";
      };
      api.listen = "127.0.0.1:1984";
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
  };
}
