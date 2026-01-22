{ config, lib, pkgs, ... }:
let
  format = pkgs.formats.yaml { };
  go2rtcConfigTemplate = format.generate "go2rtc.yaml" {
    api.listen = "0.0.0.0:1984";
    rtsp.listen = "0.0.0.0:8554";
    streams = {
      ranger_duo_fxd = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.0.2.21:554/cam/realmonitor?channel=2&subtype=0";
      ranger_duo_fxd_sub = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.0.2.21:554/cam/realmonitor?channel=2&subtype=1";
      ranger_duo_ptz = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.0.2.21:554/cam/realmonitor?channel=1&subtype=0";
      ranger_duo_ptz_sub = "rtsp://admin:@@RANGER_DUO_PASSWORD@@@192.0.2.21:554/cam/realmonitor?channel=1&subtype=1";
      ranger_uno = "rtsp://admin:@@RANGER_UNO_PASSWORD@@@192.0.2.22:554/cam/realmonitor?channel=1&subtype=0";
      ranger_uno_sub = "rtsp://admin:@@RANGER_UNO_PASSWORD@@@192.0.2.22:554/cam/realmonitor?channel=1&subtype=1";
    };
  };
in
{
  services.go2rtc = {
    enable = true;
    settings = { };
  };

  systemd.services.go2rtc = {
    serviceConfig = {
      PermissionsStartOnly = true;
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "go2rtc-apply-secrets" ''
          install -d -m 0750 /var/lib/go2rtc
          config_path="/var/lib/go2rtc/go2rtc.yaml"
          cp ${go2rtcConfigTemplate} "$config_path"
          ${pkgs.python3}/bin/python - <<'PY'
          from pathlib import Path

          replacements = {
            "@@RANGER_DUO_PASSWORD@@": Path("/run/secrets/surveillance.go2rtc.ranger_duo.password").read_text().strip(),
            "@@RANGER_UNO_PASSWORD@@": Path("/run/secrets/surveillance.go2rtc.ranger_uno.password").read_text().strip(),
          }
          config_path = Path("/var/lib/go2rtc/go2rtc.yaml")
          content = config_path.read_text()
          for placeholder, secret in replacements.items():
            content = content.replace(placeholder, secret)
          config_path.write_text(content)
          PY
          chown go2rtc:go2rtc "$config_path"
          chmod 0640 "$config_path"
        '')
      ];
      ExecStart = lib.mkForce "${config.services.go2rtc.package}/bin/go2rtc -config /var/lib/go2rtc/go2rtc.yaml";
    };
  };

}
