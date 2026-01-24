{ config, lib, pkgs, ... }:
let
  cfg = config.services.go2rtc;
  format = pkgs.formats.yaml { };
  configFile = format.generate "go2rtc.yaml" cfg.settings;
in
{
  users.groups.go2rtc = { };
  users.users.go2rtc = {
    isSystemUser = true;
    group = "go2rtc";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/go2rtc 0750 go2rtc go2rtc - -"
  ];

  services.go2rtc = {
    enable = true;
    settings = {
      api.listen = "127.0.0.1:1984";
      api.origin = "*";
      rtsp.listen = "127.0.0.1:8554";
      webrtc = {
        listen = ":8555";
        candidates = [
          "192.168.1.10:8555"
        ];
      };
      streams = {
        ranger_duo_fxd = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.168.1.21:554/cam/realmonitor?channel=2&subtype=0";
        ranger_duo_fxd_sub = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.168.1.21:554/cam/realmonitor?channel=2&subtype=1";
        ranger_duo_ptz = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.168.1.21:554/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif";
        ranger_duo_ptz_sub = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.168.1.21:554/cam/realmonitor?channel=1&subtype=1#backchannel=0";
        ranger_uno = "rtsp://admin:@@RANGER_UNO_PASSWORD@@@192.168.1.22:554/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif";
        ranger_uno_sub = "rtsp://admin:@@RANGER_UNO_PASSWORD@@@192.168.1.22:554/cam/realmonitor?channel=1&subtype=1#backchannel=0";
      };
    };
  };

  systemd.services.go2rtc = {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      StateDirectory = lib.mkForce [ ];
      User = "go2rtc";
      Group = "go2rtc";
      PermissionsStartOnly = true;
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "go2rtc-apply-secrets" ''
          install -d -m 0750 -o go2rtc -g go2rtc /run/go2rtc
          cp ${configFile} /run/go2rtc/go2rtc.yaml
          ${pkgs.python3}/bin/python - <<'PY'
          from pathlib import Path

          replacements = {
            "@@RANGER_DUO_PASSWORD@@": Path("/run/secrets/surveillance.go2rtc.ranger_duo.password").read_text().strip(),
            "@@RANGER_UNO_PASSWORD@@": Path("/run/secrets/surveillance.go2rtc.ranger_uno.password").read_text().strip(),
          }
          config_path = Path("/run/go2rtc/go2rtc.yaml")
          content = config_path.read_text()
          for placeholder, secret in replacements.items():
            content = content.replace(placeholder, secret)
          config_path.write_text(content)
          PY
          chown go2rtc:go2rtc /var/lib/go2rtc
          chown go2rtc:go2rtc "/run/go2rtc/go2rtc.yaml"
          chmod 0640 "/run/go2rtc/go2rtc.yaml"
        '')
      ];
      ExecStart = lib.mkForce "${config.services.go2rtc.package}/bin/go2rtc -config /run/go2rtc/go2rtc.yaml";
    };
  };

}
